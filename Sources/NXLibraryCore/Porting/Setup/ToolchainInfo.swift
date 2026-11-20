import Foundation

public struct ToolchainInfo: Codable, Equatable {
    public var engineCommit: String?
    public var metalVersion: String?
    public var xcodeVersion: String?
    public var verified: Bool
    public var note: String?

    public init(engineCommit: String? = nil, metalVersion: String? = nil,
                xcodeVersion: String? = nil, verified: Bool = false,
                note: String? = nil) {
        self.engineCommit = engineCommit
        self.metalVersion = metalVersion
        self.xcodeVersion = xcodeVersion
        self.verified = verified
        self.note = note
    }
}
