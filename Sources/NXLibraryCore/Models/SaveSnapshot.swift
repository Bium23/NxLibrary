import Foundation

public struct SaveIdentity: Codable, Equatable {
    public var titleID: String
    public var gameName: String
    public var version: String?
    public var buildID: String?
    public init(titleID: String, gameName: String, version: String?, buildID: String?) {
        self.titleID = titleID; self.gameName = gameName; self.version = version; self.buildID = buildID
    }
}
public enum SaveSnapshotReason: String, Codable { case manual, beforeImport, beforeRestore }
public struct SaveInventoryEntry: Codable, Equatable {
    public var slot: SaveSlot
    public var path: String
    public var isDirectory: Bool
    public var byteCount: Int64
    public var sha256: String
    public var attributes: [String: Data]
}
public struct SaveSnapshot: Codable, Equatable, Identifiable {
    public var schemaVersion = 1
    public var id: UUID
    public var identity: SaveIdentity
    public var created: Date
    public var reason: SaveSnapshotReason
    public var presentSlots: Set<SaveSlot>
    public var entries: [SaveInventoryEntry]
    public var byteCount: Int64 { entries.reduce(0) { $0 + $1.byteCount } }
}
public struct SaveImportPreview: Equatable {
    public let id: UUID
    public let source: URL
    public let staging: URL
    public let slot: SaveSlot
    public let entries: [SaveInventoryEntry]
    public let currentEntries: [SaveInventoryEntry]
    public var fileCount: Int { entries.filter { !$0.isDirectory }.count }
    public var byteCount: Int64 { entries.reduce(0) { $0 + $1.byteCount } }
}
