import Foundation

public struct CatalogSourceConfiguration: Codable, Equatable, Sendable {
    public let integration: CatalogIntegration
    public var isEnabled: Bool
    public var rootURL: URL?
    public internal(set) var generation: UUID

    public init(integration: CatalogIntegration, isEnabled: Bool = false, rootURL: URL? = nil, generation: UUID = UUID()) {
        self.integration = integration; self.isEnabled = isEnabled; self.rootURL = rootURL; self.generation = generation
    }
    private enum CodingKeys: String, CodingKey { case integration, isEnabled, rootURL, generation }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        integration = try c.decode(CatalogIntegration.self, forKey: .integration)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        rootURL = try c.decodeIfPresent(URL.self, forKey: .rootURL)
        // Older schema-one files predate source generations. Use a stable
        // sentinel until the first explicit source configuration transaction.
        generation = try c.decodeIfPresent(UUID.self, forKey: .generation)
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    }

}

/// Fingerprint of the untouched legacy input, not another writable catalog.
public struct CatalogLegacyOrigin: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case absent, primary, backup }
    public let kind: Kind
    public let sha256: String?
    public static let absent = Self(kind: .absent, sha256: nil)
}

public struct CatalogDocument: Codable, Equatable {
    public let schemaVersion: Int
    public internal(set) var revision: UUID
    public let legacyOrigin: CatalogLegacyOrigin
    public var sources: [CatalogSourceConfiguration]
    public var games: [CatalogGame]

    public init(schemaVersion: Int = 1, revision: UUID = UUID(), legacyOrigin: CatalogLegacyOrigin = .absent,
                sources: [CatalogSourceConfiguration] = [.init(integration: .nxnative), .init(integration: .steam)],
                games: [CatalogGame] = []) {
        self.schemaVersion = schemaVersion; self.revision = revision; self.legacyOrigin = legacyOrigin
        self.sources = sources; self.games = games
    }

    public func source(_ integration: CatalogIntegration) -> CatalogSourceConfiguration? {
        sources.first { $0.integration == integration }
    }

    public static func converting(_ legacy: LibraryFile, origin: CatalogLegacyOrigin = .absent) throws -> Self {
        guard legacy.schemaVersion == 1 else { throw CatalogModelError.unsupportedSchema(legacy.schemaVersion) }
        let result = Self(legacyOrigin: origin, sources: [.init(integration: .nxnative, isEnabled: true), .init(integration: .steam)],
                          games: legacy.games.map { .init(nxnative: $0) })
        try result.validate()
        return result
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw CatalogModelError.unsupportedSchema(schemaVersion) }
        guard Set(sources.map(\.integration)).count == sources.count else { throw CatalogModelError.invalidRecord }
        switch legacyOrigin.kind {
        case .absent: guard legacyOrigin.sha256 == nil else { throw CatalogModelError.invalidRecord }
        case .primary, .backup:
            guard let digest = legacyOrigin.sha256, digest.utf8.count == 64,
                  digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw CatalogModelError.invalidRecord }
        }
        for source in sources {
            if let root = source.rootURL, !root.isFileURL { throw CatalogModelError.invalidRecord }
            if source.integration == .steam && source.isEnabled && source.rootURL == nil { throw CatalogModelError.invalidRecord }
        }
        var ids = Set<UUID>(), appIDs = Set<UInt32>(), installationIDs = Set<UUID>()
        for game in games {
            try game.validateRecord()
            guard ids.insert(game.id).inserted else { throw CatalogModelError.duplicateGameID }
            if let steam = game.steamGame {
                guard appIDs.insert(steam.appID).inserted else { throw CatalogModelError.duplicateSteamAppID }
                for installation in steam.installations {
                    guard installationIDs.insert(installation.id).inserted else { throw CatalogModelError.duplicateInstallationID }
                }
            }
        }
    }
}
