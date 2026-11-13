import Foundation

/// Only explicit operations created in this Dev profile may resume automatically after a restart.
/// This file is deliberately absent from the stable-to-development import allowlist.
public final class DevelopmentOperationStore {
    public enum Kind: String, Codable { case build, icon }
    private let file: URL
    private let isDevelopment: Bool
    private var requested: [String: Set<UUID>] = [:]
    public private(set) var loadError: Error?

    public init(file: URL = AppData.supportRoot.appendingPathComponent(".development-operations.json"),
                isDevelopment: Bool = AppData.profile.isDevelopment) {
        self.file = file
        self.isDevelopment = isDevelopment
        guard isDevelopment, FileManager.default.fileExists(atPath: file.path) else { return }
        do { requested = try JSONDecoder().decode([String: Set<UUID>].self, from: Data(contentsOf: file)) }
        catch { loadError = error }
    }
    public func permits(_ kind: Kind, gameID: UUID) -> Bool {
        !isDevelopment || (loadError == nil && requested[kind.rawValue]?.contains(gameID) == true)
    }
    public func authorize(_ kind: Kind, gameID: UUID) throws {
        guard isDevelopment else { return }
        if let loadError { throw loadError }
        var next = requested
        next[kind.rawValue, default: []].insert(gameID)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
        requested = next
    }
}
