import Foundation
import Darwin
import NXLibraryCore

public final class SaveTransaction {
    private let store: SaveSnapshotStore
    private let isRunning: () -> Bool
    private let validateAccess: () throws -> Void
    private let io: SaveFileIO
    private struct Journal: Codable {
        var version = 1
        let id: UUID
        let titleID: String
        let before: UUID
        let after: [SaveInventoryEntry]
        /// Missing in historical journals, which mutate the two legacy slots.
        var mutatedSlots: Set<SaveSlot>?
        /// Durable deletion intent: remaining staging entries must be a subset of these verified trees.
        var cleanupArtifacts: [String: [SaveInventoryEntry]]? = nil
        var committed: Bool

        var observedSlots: [SaveSlot] { version == 1 ? SaveSlot.legacyCases : SaveSlot.allCases }
        var mutationOrder: [SaveSlot] { observedSlots.filter { mutatedSlots?.contains($0) ?? true } }
        var isValid: Bool {
            guard version == 1 || version == 2, version == 1 || mutatedSlots != nil,
                  !mutationOrder.isEmpty else { return false }
            let allowed = Set(observedSlots)
            guard mutatedSlots?.isSubset(of: allowed) ?? true,
                  after.allSatisfy({ allowed.contains($0.slot) && ($0.path.isEmpty || SaveFiles.validRelative($0.path))
                      && $0.byteCount >= 0 && ($0.slot != .users || (!$0.isDirectory && $0.path.isEmpty && $0.byteCount <= 65536)) })
            else { return false }
            guard Set(after.map { $0.slot.rawValue + ":" + $0.path }).count == after.count else { return false }
            for (name, entries) in cleanupArtifacts ?? [:] {
                guard let slot = mutationOrder.first(where: { name == $0.rawValue || name == "rollback-" + $0.rawValue }),
                      entries.allSatisfy({ $0.slot == slot && ($0.path.isEmpty || SaveFiles.validRelative($0.path)) }) else { return false }
            }
            return true
        }
    }
    public init(store: SaveSnapshotStore, isRunning: @escaping () -> Bool,
                validateAccess: @escaping () throws -> Void = {}) {
        self.store = store; self.isRunning = isRunning; self.validateAccess = validateAccess; self.io = store.io
    }
    internal init(store: SaveSnapshotStore, isRunning: @escaping () -> Bool, io: SaveFileIO) {
        self.store = store; self.isRunning = isRunning; self.validateAccess = {}; self.io = io
    }
    private func journalURL(_ location: SaveLocation) -> URL { location.root.appendingPathComponent(".nxlibrary-save-transaction.json") }
    private func staging(_ id: UUID, _ location: SaveLocation) -> URL { location.root.appendingPathComponent(".nxlibrary-save-transaction-\(id)") }
    public static func needsRecovery(location: SaveLocation) -> Bool {
        SaveFiles.exists(location.root.appendingPathComponent(".nxlibrary-save-transaction.json"))
    }
    private func check(_ location: SaveLocation) throws {
        guard !isRunning() else { throw SaveFailure.running }
        try location.validate(); try validateAccess()
    }
    @discardableResult
    public func importSave(_ preview: SaveImportPreview, location: SaveLocation, identity: SaveIdentity) throws -> SaveSnapshot {
        try check(location)
        try store.validate(preview, location: location)
        return try replace(location: location, identity: identity, reason: .beforeImport, slots: [preview.slot],
            desired: { _ in preview.staging }, revalidate: { try self.store.validate(preview, location: location) })
    }
    @discardableResult
    public func restore(_ snapshot: SaveSnapshot, location: SaveLocation, identity: SaveIdentity) throws -> SaveSnapshot {
        try check(location)
        let preview = try store.stageRestore(snapshot, location: location)
        defer { try? store.discardRestore(preview, location: location) }
        return try restore(preview, location: location, identity: identity)
    }
    @discardableResult
    public func restore(_ preview: SaveRestorePreview, location: SaveLocation, identity: SaveIdentity) throws -> SaveSnapshot {
        try check(location)
        guard identity.titleID == location.titleID else { throw SaveFailure.invalidSnapshot }
        try store.validateRestore(preview, location: location)
        let slots = preview.snapshot.schemaVersion == 1 ? SaveSlot.legacyCases : SaveSlot.allCases
        return try replace(location: location, identity: identity, reason: .beforeRestore, slots: slots,
            desired: { preview.staging.appendingPathComponent($0.fileName) },
            revalidate: { try self.store.validateRestore(preview, location: location) })
    }
    private func replace(location: SaveLocation, identity: SaveIdentity, reason: SaveSnapshotReason, slots: [SaveSlot],
                         desired: (SaveSlot) -> URL, revalidate: () throws -> Void) throws -> SaveSnapshot {
        guard !Self.needsRecovery(location: location) else { throw SaveFailure.recoveryRequired }
        guard !SaveFiles.exists(location.cloudPullJournal) else { throw SaveFailure.cloudPullPending }
        try check(location)
        let previous = try SaveFiles.inventory(location)
        let id = UUID(), stage = staging(id, location)
        try SaveFiles.makeDirectory(stage)
        var journalWritten = false
        defer { if !journalWritten { try? SaveFiles.remove(stage) } }
        var after: [SaveInventoryEntry] = []
        for slot in SaveSlot.allCases {
            guard slots.contains(slot) else { after += previous.filter { $0.slot == slot }; continue }
            let source = desired(slot)
            let entries = try SaveFiles.inventory(source, slot: slot)
            after += entries
            if !entries.isEmpty {
                let next = stage.appendingPathComponent(slot.rawValue)
                try io.copy(source, next)
                guard try SaveFiles.inventory(next, slot: slot) == entries else { throw SaveFailure.changed }
                try SaveFiles.syncTree(next)
            }
        }
        try SaveFiles.syncDirectory(stage)
        try revalidate(); try check(location)
        guard try SaveFiles.inventory(location) == previous else { throw SaveFailure.changed }
        let safety = try store.create(location: location, identity: identity, reason: reason)
        guard safety.entries == previous else { throw SaveFailure.changed }
        try revalidate(); try check(location)
        guard try SaveFiles.inventory(location) == previous else { throw SaveFailure.changed }
        let version = previous.allSatisfy({ $0.slot.isLegacy }) && after.allSatisfy({ $0.slot.isLegacy })
            && slots.allSatisfy(\.isLegacy) ? 1 : 2
        var journal = Journal(version: version, id: id, titleID: location.titleID, before: safety.id,
                              after: after, mutatedSlots: Set(slots), committed: false)
        try SaveFiles.durableWrite(journal, to: journalURL(location))
        journalWritten = true
        do {
            try io.afterMutation("journal")
            for slot in journal.mutationOrder {
                try check(location)
                try io.afterMutation("before-" + slot.rawValue)
                let next = stage.appendingPathComponent(slot.rawValue)
                guard try SaveFiles.inventory(location.directory(slot), slot: slot) == previous.filter({ $0.slot == slot }),
                      try SaveFiles.inventory(next, slot: slot) == after.filter({ $0.slot == slot }) else { throw SaveFailure.changed }
                try swap(next, into: location.directory(slot))
                try SaveFiles.syncDirectory(location.root)
                try SaveFiles.syncDirectory(stage)
                // A writer holding an old inode may change it even after the path is exchanged.
                guard try SaveFiles.inventory(next, slot: slot) == previous.filter({ $0.slot == slot }) else { throw SaveFailure.changed }
                try io.afterMutation(slot.rawValue)
            }
            try check(location)
            guard try SaveFiles.inventory(location) == after else { throw SaveFailure.recoveryRequired }
            try validateArtifacts(journal, location, before: previous)
            journal.committed = true
            try SaveFiles.durableWrite(journal, to: journalURL(location))
            try io.afterMutation("committed")
            try cleanup(journal, location, before: previous, expected: after)
            return safety
        } catch { throw SaveFailure.recoveryRequired }
    }
    /// Moves a next tree/file in, retaining the old one in staging. Absence restores absence.
    private func swap(_ next: URL, into destination: URL) throws {
        try SaveFiles.safePath(next); try SaveFiles.safePath(destination)
        if SaveFiles.exists(next) && SaveFiles.exists(destination) {
            guard renamex_np(next.path, destination.path, UInt32(RENAME_SWAP)) == 0 else { throw SaveFailure.io("Could not replace the save.") }
        } else if SaveFiles.exists(next) {
            try FileManager.default.moveItem(at: next, to: destination)
        } else if SaveFiles.exists(destination) {
            try FileManager.default.moveItem(at: destination, to: next)
        }
    }
    private func observedInventory(_ journal: Journal, _ location: SaveLocation) throws -> [SaveInventoryEntry] {
        try location.validate()
        return try journal.observedSlots.flatMap { try SaveFiles.inventory(location.directory($0), slot: $0) }
    }
    /// Never delete unrecognized or externally changed data from a managed transaction folder.
    private func validateArtifacts(_ journal: Journal, _ location: SaveLocation, before: [SaveInventoryEntry]) throws {
        let stage = staging(journal.id, location)
        try SaveFiles.safePath(stage)
        guard SaveFiles.exists(stage) else { return }
        let portableAfter = journal.after.map(\.portable)
        for child in try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil) {
            guard let slot = journal.mutationOrder.first(where: {
                child.lastPathComponent == $0.rawValue || child.lastPathComponent == "rollback-" + $0.rawValue
            }) else { throw SaveFailure.recoveryRequired }
            let entries = try SaveFiles.inventory(child, slot: slot)
            guard entries == before.filter({ $0.slot == slot }) || entries == portableAfter.filter({ $0.slot == slot }) else {
                throw SaveFailure.recoveryRequired
            }
        }
    }
    public func recover(location: SaveLocation) throws {
        guard Self.needsRecovery(location: location) else { return }
        // Recovery is local rollback, not a new import: cloud settings do not prevent it.
        guard !isRunning() else { throw SaveFailure.running }
        try location.validate()
        let file = journalURL(location)
        try SaveFiles.safePath(file)
        guard let data = try? SaveFiles.readRegular(file, limit: 96 * 1024 * 1024),
              let journal = try? JSONDecoder().decode(Journal.self, from: data), journal.isValid,
              journal.titleID == location.titleID else { throw SaveFailure.recoveryRequired }
        let original = try store.verify(snapshotID: journal.before, titleID: location.titleID)
        guard journal.version != 1 || original.schemaVersion == 1 else { throw SaveFailure.recoveryRequired }
        let expectedAfter = journal.after.map(\.portable)
        let before = original.entries.filter { journal.observedSlots.contains($0.slot) }
        if journal.cleanupArtifacts != nil || journal.committed {
            try cleanup(journal, location, before: before, expected: journal.committed ? expectedAfter : before)
            return
        }
        if try observedInventory(journal, location) == before {
            try cleanup(journal, location, before: before, expected: before)
            return
        }
        try validateArtifacts(journal, location, before: before)
        do {
            let backup = try store.directory(snapshotID: journal.before, titleID: location.titleID)
            let stage = staging(journal.id, location)
            try SaveFiles.makeDirectory(stage)
            for slot in journal.mutationOrder {
                guard !isRunning() else { throw SaveFailure.running }
                let current = try SaveFiles.inventory(location.directory(slot), slot: slot)
                let previous = before.filter { $0.slot == slot }
                let after = expectedAfter.filter { $0.slot == slot }
                if current == previous { continue }
                guard current == after else { throw SaveFailure.recoveryRequired }
                let rollback = stage.appendingPathComponent("rollback-" + slot.rawValue)
                try validateArtifacts(journal, location, before: before)
                try SaveFiles.remove(rollback)
                if original.presentSlots.contains(slot) {
                    try io.copy(backup.appendingPathComponent(slot.fileName), rollback)
                    guard try SaveFiles.inventory(rollback, slot: slot) == previous else { throw SaveFailure.invalidSnapshot }
                    try SaveFiles.syncTree(rollback)
                }
                try location.validate()
                guard try SaveFiles.inventory(location.directory(slot), slot: slot) == after else { throw SaveFailure.recoveryRequired }
                try swap(rollback, into: location.directory(slot))
                try SaveFiles.syncDirectory(location.root)
                try SaveFiles.syncDirectory(stage)
                guard try SaveFiles.inventory(rollback, slot: slot) == after else { throw SaveFailure.recoveryRequired }
                try io.afterMutation("recovery-" + slot.rawValue)
            }
            guard try observedInventory(journal, location) == before else { throw SaveFailure.recoveryRequired }
        }
        try cleanup(journal, location, before: before, expected: before)
    }

    private func isSubset(_ actual: [SaveInventoryEntry], of expected: [SaveInventoryEntry]) -> Bool {
        var byPath: [String: SaveInventoryEntry] = [:]
        for entry in expected.map(\.portable) {
            guard byPath.updateValue(entry, forKey: entry.path) == nil else { return false }
        }
        return actual.allSatisfy { byPath[$0.path] == $0 }
    }

    private func cleanupRecord(_ journal: Journal, _ location: SaveLocation, before: [SaveInventoryEntry]) throws -> [String: [SaveInventoryEntry]] {
        let stage = staging(journal.id, location)
        try SaveFiles.safePath(stage)
        guard SaveFiles.exists(stage) else { return [:] }
        var records: [String: [SaveInventoryEntry]] = [:]
        for child in try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil) {
            guard let slot = journal.mutationOrder.first(where: {
                child.lastPathComponent == $0.rawValue || child.lastPathComponent == "rollback-" + $0.rawValue
            }) else { throw SaveFailure.recoveryRequired }
            let actual = try SaveFiles.inventory(child, slot: slot)
            let candidates = [before.filter { $0.slot == slot }, journal.after.filter { $0.slot == slot }.map(\.portable)]
            guard let known = candidates.first(where: { isSubset(actual, of: $0) }) else { throw SaveFailure.recoveryRequired }
            records[child.lastPathComponent] = known
        }
        return records
    }

    private func removeCleanupArtifacts(_ journal: Journal, _ location: SaveLocation) throws {
        let stage = staging(journal.id, location)
        try SaveFiles.safePath(stage)
        guard SaveFiles.exists(stage), let records = journal.cleanupArtifacts else { return }
        let children = try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil)
        guard children.allSatisfy({ records[$0.lastPathComponent] != nil }) else { throw SaveFailure.recoveryRequired }
        for child in children {
            let expected = records[child.lastPathComponent]!
            guard let slot = journal.mutationOrder.first(where: { child.lastPathComponent == $0.rawValue || child.lastPathComponent == "rollback-" + $0.rawValue }),
                  isSubset(try SaveFiles.inventory(child, slot: slot), of: expected) else { throw SaveFailure.recoveryRequired }
            // Reverse preorder: children before their parent. unlink/rmdir never recursively delete surprises.
            for entry in expected.reversed() {
                guard !isRunning() else { throw SaveFailure.running }
                let url = entry.path.isEmpty ? child : child.appendingPathComponent(entry.path)
                try SaveFiles.safePath(url)
                guard SaveFiles.exists(url) else { continue }
                var actual = try SaveFiles.inventory(url, slot: slot, componentRoot: false)
                guard actual.count == 1 else { throw SaveFailure.recoveryRequired }
                actual[0].path = entry.path
                guard actual[0] == entry.portable else { throw SaveFailure.recoveryRequired }
                let result = entry.isDirectory ? rmdir(url.path) : unlink(url.path)
                guard result == 0 else { throw SaveFailure.recoveryRequired }
                try io.afterMutation("cleanup-item")
            }
        }
        guard rmdir(stage.path) == 0 else { throw SaveFailure.recoveryRequired }
        try io.afterMutation("cleanup-stage")
    }

    private func cleanup(_ journal: Journal, _ location: SaveLocation, before: [SaveInventoryEntry], expected: [SaveInventoryEntry]) throws {
        guard !isRunning(), try observedInventory(journal, location) == expected else { throw SaveFailure.recoveryRequired }
        var cleaning = journal
        if cleaning.cleanupArtifacts == nil {
            cleaning.cleanupArtifacts = try cleanupRecord(journal, location, before: before)
            try SaveFiles.durableWrite(cleaning, to: journalURL(location))
            try io.afterMutation("cleanup")
        }
        try removeCleanupArtifacts(cleaning, location)
        try SaveFiles.syncDirectory(location.root)
        try SaveFiles.remove(journalURL(location))
        try SaveFiles.syncDirectory(location.root)
    }
}

extension SaveFiles {
    static func syncTree(_ directory: URL) throws {
        try safePath(directory)
        var info = stat()
        guard lstat(directory.path, &info) == 0 else { throw SaveFailure.changed }
        if (info.st_mode & S_IFMT) == S_IFREG {
            let fd = open(directory.path, O_RDONLY | O_NOFOLLOW)
            guard fd >= 0 else { throw SaveFailure.io("Could not persist the staged save.") }
            defer { close(fd) }
            guard fsync(fd) == 0 else { throw SaveFailure.io("Could not persist the staged save.") }
        } else {
            guard (info.st_mode & S_IFMT) == S_IFDIR else { throw SaveFailure.unsafePath }
            for child in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) { try syncTree(child) }
            try syncDirectory(directory)
        }
    }
}
