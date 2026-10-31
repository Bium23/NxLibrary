import Foundation
import Darwin

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
        var committed: Bool
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
        return try replace(location: location, identity: identity, reason: .beforeImport,
            desired: { slot in slot == preview.slot ? preview.staging : location.directory(slot) },
            revalidate: { try self.store.validate(preview, location: location) })
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
        return try replace(location: location, identity: identity, reason: .beforeRestore,
            desired: { preview.staging.appendingPathComponent($0 == .account ? "save" : "save_device") },
            revalidate: { try self.store.validateRestore(preview, location: location) })
    }
    private func replace(location: SaveLocation, identity: SaveIdentity, reason: SaveSnapshotReason,
                         desired: (SaveSlot) -> URL, revalidate: () throws -> Void) throws -> SaveSnapshot {
        guard !Self.needsRecovery(location: location) else { throw SaveFailure.recoveryRequired }
        try check(location)
        let previous = try SaveFiles.inventory(location)
        let id = UUID(); let stage = staging(id, location)
        try SaveFiles.makeDirectory(stage)
        var journalWritten = false
        defer { if !journalWritten { try? SaveFiles.remove(stage) } }
        var after: [SaveInventoryEntry] = []
        for slot in SaveSlot.allCases {
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
        try revalidate(); try check(location)
        guard try SaveFiles.inventory(location) == previous else { throw SaveFailure.changed }
        let safety = try store.create(location: location, identity: identity, reason: reason)
        guard safety.entries == previous else { throw SaveFailure.changed }
        try revalidate(); try check(location)
        guard try SaveFiles.inventory(location) == previous else { throw SaveFailure.changed }
        var journal = Journal(id: id, titleID: location.titleID, before: safety.id, after: after, committed: false)
        try SaveFiles.durableWrite(journal, to: journalURL(location))
        journalWritten = true
        do {
            try io.afterMutation("journal")
            for slot in SaveSlot.allCases {
                try check(location)
                try swap(stage.appendingPathComponent(slot.rawValue), into: location.directory(slot))
                try SaveFiles.syncDirectory(location.root)
                try io.afterMutation(slot.rawValue)
            }
            guard try SaveFiles.inventory(location) == after else { throw SaveFailure.recoveryRequired }
            journal.committed = true
            try SaveFiles.durableWrite(journal, to: journalURL(location))
            try io.afterMutation("committed")
            try cleanup(journal, location)
            return safety
        } catch { throw SaveFailure.recoveryRequired }
    }
    /// Moves a next tree in, retaining the old one in staging. An absent next tree means restore absence.
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
    public func recover(location: SaveLocation) throws {
        guard Self.needsRecovery(location: location) else { return }
        // Recovery is local rollback, not a new import: cloud settings do not prevent it.
        guard !isRunning() else { throw SaveFailure.running }
        try location.validate()
        let file = journalURL(location)
        try SaveFiles.safePath(file)
        guard let data = try? SaveFiles.readRegular(file, limit: 32 * 1024 * 1024),
              let journal = try? JSONDecoder().decode(Journal.self, from: data), journal.version == 1,
              journal.titleID == location.titleID,
              journal.after.allSatisfy({ $0.path.isEmpty || SaveFiles.validRelative($0.path) }) else { throw SaveFailure.recoveryRequired }
        let original = try store.verify(snapshotID: journal.before, titleID: location.titleID)
        if journal.committed {
            guard try SaveFiles.inventory(location) == journal.after else { throw SaveFailure.recoveryRequired }
        } else {
            let backup = try store.directory(snapshotID: journal.before, titleID: location.titleID)
            let stage = staging(journal.id, location)
            try SaveFiles.makeDirectory(stage)
            for slot in SaveSlot.allCases {
                guard !isRunning() else { throw SaveFailure.running }
                let current = try SaveFiles.inventory(location.directory(slot), slot: slot)
                let before = original.entries.filter { $0.slot == slot }
                let after = journal.after.filter { $0.slot == slot }
                if current == before { continue }
                // Never destroy a save modified outside this transaction.
                guard current == after else { throw SaveFailure.recoveryRequired }
                let rollback = stage.appendingPathComponent("rollback-\(slot.rawValue)")
                try SaveFiles.remove(rollback)
                if original.presentSlots.contains(slot) {
                    try io.copy(backup.appendingPathComponent(slot == .account ? "save" : "save_device"), rollback)
                    guard try SaveFiles.inventory(rollback, slot: slot) == before else { throw SaveFailure.invalidSnapshot }
                    try SaveFiles.syncTree(rollback)
                }
                try location.validate()
                try swap(rollback, into: location.directory(slot))
                try SaveFiles.syncDirectory(location.root)
            }
            guard try SaveFiles.inventory(location) == original.entries else { throw SaveFailure.recoveryRequired }
        }
        try cleanup(journal, location)
    }
    private func cleanup(_ journal: Journal, _ location: SaveLocation) throws {
        try SaveFiles.remove(staging(journal.id, location))
        try SaveFiles.remove(journalURL(location))
        try SaveFiles.syncDirectory(location.root)
    }
}

extension SaveFiles {
    static func syncTree(_ directory: URL) throws {
        try safePath(directory)
        let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        for child in children {
            if try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { try syncTree(child) }
            else {
                let fd = open(child.path, O_RDONLY | O_NOFOLLOW)
                guard fd >= 0 else { throw SaveFailure.io("Could not persist the staged save.") }
                let result = fsync(fd); close(fd)
                guard result == 0 else { throw SaveFailure.io("Could not persist the staged save.") }
            }
        }
        try syncDirectory(directory)
    }
}
