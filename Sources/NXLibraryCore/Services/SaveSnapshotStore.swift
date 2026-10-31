import Foundation

public final class SaveSnapshotStore {
    public let root: URL
    internal let io: SaveFileIO
    public init(root: URL) { self.root = root; self.io = SaveFileIO() }
    internal init(root: URL, io: SaveFileIO) { self.root = root; self.io = io }
    private func titleRoot(_ titleID: String) throws -> URL {
        guard SaveLocation.validID(titleID) else { throw SaveFailure.invalidTitleID }
        let url = root.appendingPathComponent(titleID.uppercased())
        try SaveFiles.safePath(url); return url
    }
    public func create(location: SaveLocation, identity: SaveIdentity, reason: SaveSnapshotReason) throws -> SaveSnapshot {
        guard identity.titleID == location.titleID else { throw SaveFailure.invalidSnapshot }
        let before = try SaveFiles.inventory(location)
        try SaveFiles.checkSpace(at: root, bytes: before.reduce(0) { $0 + $1.byteCount })
        let id = UUID(); let created = Date()
        let parent = try titleRoot(location.titleID)
        try SaveFiles.makeDirectory(parent)
        let temp = parent.appendingPathComponent(".creating-\(id)")
        try SaveFiles.makeDirectory(temp)
        defer { try? SaveFiles.remove(temp) }
        let slots = Set(before.map(\.slot))
        for slot in SaveSlot.allCases where slots.contains(slot) {
            try io.copy(location.directory(slot), temp.appendingPathComponent(slot == .account ? "save" : "save_device"))
        }
        guard try SaveFiles.inventory(location) == before else { throw SaveFailure.changed }
        let snapshot = SaveSnapshot(id: id, identity: identity, created: created, reason: reason, presentSlots: slots, entries: before)
        try verifyContents(snapshot, directory: temp)
        try SaveFiles.syncTree(temp)
        try SaveFiles.durableWrite(snapshot, to: temp.appendingPathComponent("manifest.json"))
        let final = parent.appendingPathComponent("\(Int64(created.timeIntervalSince1970 * 1000))-\(id)")
        try FileManager.default.moveItem(at: temp, to: final)
        try SaveFiles.syncDirectory(parent)
        return snapshot
    }
    public func list(titleID: String) throws -> [SaveSnapshot] {
        let parent = try titleRoot(titleID)
        guard SaveFiles.exists(parent) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { try readManifest($0, titleID: titleID) }.sorted { $0.created > $1.created }
    }
    public func directory(snapshotID: UUID, titleID: String) throws -> URL {
        let parent = try titleRoot(titleID)
        let candidates = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent.hasSuffix("-\(snapshotID)") }
        guard candidates.count == 1 else { throw SaveFailure.invalidSnapshot }
        try SaveFiles.safePath(candidates[0]); return candidates[0]
    }
    public func verify(snapshotID: UUID, titleID: String) throws -> SaveSnapshot {
        let url = try directory(snapshotID: snapshotID, titleID: titleID)
        let snapshot = try readManifest(url, titleID: titleID)
        guard snapshot.id == snapshotID else { throw SaveFailure.invalidSnapshot }
        try verifyContents(snapshot, directory: url)
        return snapshot
    }
    private func readManifest(_ directory: URL, titleID: String) throws -> SaveSnapshot {
        let file = directory.appendingPathComponent("manifest.json")
        try SaveFiles.safePath(file)
        guard let data = try? SaveFiles.readRegular(file, limit: 32 * 1024 * 1024),
              let snapshot = try? JSONDecoder().decode(SaveSnapshot.self, from: data),
              snapshot.schemaVersion == 1, snapshot.identity.titleID == titleID.uppercased(),
              snapshot.entries.allSatisfy({ ($0.path.isEmpty || SaveFiles.validRelative($0.path)) && $0.byteCount >= 0 && $0.byteCount < Int64.max / Int64(max(1, snapshot.entries.count)) }) else { throw SaveFailure.invalidSnapshot }
        return snapshot
    }
    internal func verifyContents(_ snapshot: SaveSnapshot, directory: URL) throws {
        var actual: [SaveInventoryEntry] = []
        for slot in SaveSlot.allCases {
            actual += try SaveFiles.inventory(directory.appendingPathComponent(slot == .account ? "save" : "save_device"), slot: slot)
        }
        guard actual == snapshot.entries, Set(actual.map(\.slot)) == snapshot.presentSlots else { throw SaveFailure.invalidSnapshot }
    }
    public func currentInventory(location: SaveLocation) throws -> [SaveInventoryEntry] { try SaveFiles.inventory(location) }
    public func stageImport(source: URL, slot: SaveSlot, location: SaveLocation) throws -> SaveImportPreview {
        try location.validate()
        try SaveFiles.safePath(source)
        let source = source.standardizedFileURL
        let managed = [location.root, root]
        guard !managed.contains(where: { source.path == $0.path || source.path.hasPrefix($0.path + "/") || $0.path.hasPrefix(source.path + "/") }) else { throw SaveFailure.unsafePath }
        let entries = try SaveFiles.inventory(source, slot: slot)
        guard entries.contains(where: { !$0.isDirectory }) else { throw SaveFailure.emptyImport }
        let current = try SaveFiles.inventory(location)
        try SaveFiles.checkSpace(at: location.root, bytes: entries.reduce(0) { $0 + $1.byteCount })
        try SaveFiles.makeDirectory(location.root)
        let id = UUID(); let staging = location.root.appendingPathComponent(".nxlibrary-save-preview-\(id)")
        do {
            try io.copy(source, staging)
            guard try SaveFiles.inventory(source, slot: slot) == entries,
                  try SaveFiles.inventory(staging, slot: slot) == entries else { throw SaveFailure.changed }
        } catch { try? SaveFiles.remove(staging); throw error }
        return SaveImportPreview(id: id, source: source, staging: staging, slot: slot, entries: entries, currentEntries: current)
    }
    public func validate(_ preview: SaveImportPreview, location: SaveLocation) throws {
        try validateStaging(preview, location: location)
        guard try SaveFiles.inventory(preview.source, slot: preview.slot) == preview.entries,
              try SaveFiles.inventory(preview.staging, slot: preview.slot) == preview.entries,
              try SaveFiles.inventory(location) == preview.currentEntries else { throw SaveFailure.changed }
    }
    private func validateStaging(_ preview: SaveImportPreview, location: SaveLocation) throws {
        guard preview.staging.path == location.root.appendingPathComponent(".nxlibrary-save-preview-\(preview.id)").path else { throw SaveFailure.unsafePath }
        try location.validate(); try SaveFiles.safePath(preview.staging)
    }
    public func discard(_ preview: SaveImportPreview, location: SaveLocation) throws {
        try validateStaging(preview, location: location); try SaveFiles.remove(preview.staging)
    }
}
