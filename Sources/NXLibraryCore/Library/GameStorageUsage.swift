import Foundation

/// Missing files occupy no space; an unreadable folder or disconnected drive has an unknown size.
public enum StorageSize: Equatable {
    case bytes(Int64), missing, unavailable

    public var knownBytes: Int64? {
        switch self {
        case .bytes(let bytes): return bytes
        case .missing: return 0
        case .unavailable: return nil
        }
    }
}

public struct GameStorageUsage: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let app: StorageSize
    public let cache: StorageSize
    public let logs: StorageSize
    public let canDeleteCache: Bool
    public let sharedCacheWith: [String]

    public var rowID: String { "storage-game-\(id.uuidString)" }
}

public struct StorageSnapshot: Equatable {
    public let games: [GameStorageUsage]
    public let total: StorageUsage
    public let freeBytes: Int64?

    public var hasUnavailableFiles: Bool {
        games.contains { $0.app == .unavailable || $0.cache == .unavailable || $0.logs == .unavailable }
    }
}
