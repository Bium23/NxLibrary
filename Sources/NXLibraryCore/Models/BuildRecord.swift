import Foundation

public struct BuildRecord: Codable, Equatable {
    public var startedAt: Date
    public var endedAt: Date?
    public var exitCode: Int32?
    public var logPath: String?
    public var outputPath: String?
    public var engineCommit: String?
    public var metalVersion: String?
    public var xcodeVersion: String?
    public var toolchainVerified: Bool
    public var cancelled: Bool

    public init(startedAt: Date = Date(), endedAt: Date? = nil,
                exitCode: Int32? = nil, logPath: String? = nil,
                outputPath: String? = nil, engineCommit: String? = nil,
                metalVersion: String? = nil, xcodeVersion: String? = nil,
                toolchainVerified: Bool = false, cancelled: Bool = false) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exitCode = exitCode
        self.logPath = logPath
        self.outputPath = outputPath
        self.engineCommit = engineCommit
        self.metalVersion = metalVersion
        self.xcodeVersion = xcodeVersion
        self.toolchainVerified = toolchainVerified
        self.cancelled = cancelled
    }
}
