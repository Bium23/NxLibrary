import Foundation

public struct PlaySession: Codable, Identifiable, Equatable {
    public let id: UUID
    public let gameID: UUID
    public let titleID: String
    public let bundleID: String?
    public let startedAt: Date
    public var endedAt: Date?
    public var lastHeartbeatAt: Date

    public init(id: UUID = UUID(), gameID: UUID, titleID: String,
                bundleID: String?, startedAt: Date, endedAt: Date? = nil,
                lastHeartbeatAt: Date) {
        self.id = id
        self.gameID = gameID
        self.titleID = titleID
        self.bundleID = bundleID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lastHeartbeatAt = lastHeartbeatAt
    }

    public var isActive: Bool { endedAt == nil }
    public var duration: TimeInterval? {
        endedAt.map { max(0, $0.timeIntervalSince(startedAt)) }
    }
}
