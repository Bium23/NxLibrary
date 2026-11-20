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

/// Fingerprint of the legacy input at migration or the last explicit conflict
/// acknowledgement. Legacy files remain untouched, not another writable catalog.
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
    /// Games and sources of an integration this version does not know (written by a newer Arcane, or by one with a
    /// source module this one lacks), kept as read and written back after the known ones. No projection, search or
    /// screen sees them, and nothing edits them.
    public internal(set) var preservedGames: [CatalogJSON]
    public internal(set) var preservedSources: [CatalogJSON]

    public init(schemaVersion: Int = 1, revision: UUID = UUID(), legacyOrigin: CatalogLegacyOrigin = .absent,
                sources: [CatalogSourceConfiguration] = [],
                games: [CatalogGame] = [], preservedGames: [CatalogJSON] = [], preservedSources: [CatalogJSON] = []) {
        self.schemaVersion = schemaVersion; self.revision = revision; self.legacyOrigin = legacyOrigin
        self.sources = sources; self.games = games
        self.preservedGames = preservedGames; self.preservedSources = preservedSources
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, revision, legacyOrigin, sources, games }
    private enum IntegrationKey: String, CodingKey { case integration }

    /// Reads each game and source as known only when its `integration` is one of the decoder's `CatalogRecordKinds`;
    /// any other is kept.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        revision = try c.decode(UUID.self, forKey: .revision)
        legacyOrigin = try c.decode(CatalogLegacyOrigin.self, forKey: .legacyOrigin)
        let known = Set(CatalogRecordKinds.of(decoder).integrations)
        (sources, preservedSources) = try Self.split(c, .sources, known, CatalogSourceConfiguration.init(from:))
        (games, preservedGames) = try Self.split(c, .games, known, CatalogGame.init(from:))
    }

    private static func split<Known>(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, _ integrations: Set<CatalogIntegration>,
                                     _ known: (Decoder) throws -> Known) throws -> ([Known], [CatalogJSON]) {
        var list = try c.nestedUnkeyedContainer(forKey: key)
        var kept: [Known] = [], preserved: [CatalogJSON] = []
        while !list.isAtEnd {
            let element = try list.superDecoder()
            let tag = try? element.container(keyedBy: IntegrationKey.self).decode(String.self, forKey: .integration)
            if let tag, integrations.contains(CatalogIntegration(rawValue: tag)) { kept.append(try known(element)) }
            else { preserved.append(try CatalogJSON(from: element)) }
        }
        return (kept, preserved)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(revision, forKey: .revision)
        try c.encode(legacyOrigin, forKey: .legacyOrigin)
        var sourceList = c.nestedUnkeyedContainer(forKey: .sources)
        for source in sources { try sourceList.encode(source) }
        for source in preservedSources { try sourceList.encode(source) }
        var gameList = c.nestedUnkeyedContainer(forKey: .games)
        for game in games { try gameList.encode(game) }
        for game in preservedGames { try gameList.encode(game) }
    }

    public func source(_ integration: CatalogIntegration) -> CatalogSourceConfiguration? {
        sources.first { $0.integration == integration }
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw CatalogModelError.unsupportedSchema(schemaVersion) }
        let preservedIntegrations = try preservedSources.map { source -> String in
            guard let integration = source["integration"]?.stringValue else { throw CatalogModelError.invalidRecord }
            return integration
        }
        let integrations = sources.map(\.integration.rawValue) + preservedIntegrations
        guard Set(integrations).count == integrations.count else { throw CatalogModelError.invalidRecord }
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
        for game in preservedGames {
            guard game["integration"]?.stringValue != nil, case .object = game["data"] else { throw CatalogModelError.invalidRecord }
            if let id = game["data"]?["id"]?.stringValue.flatMap(UUID.init(uuidString:)) {
                guard ids.insert(id).inserted else { throw CatalogModelError.duplicateGameID }
            }
        }
    }
}
