import Foundation

public enum CatalogIntegration: String, Codable, Hashable, Sendable { case nxnative, steam }

public struct CatalogProviderIdentity: Codable, Hashable, Sendable {
    public let integration: CatalogIntegration
    public let externalID: String
}

/// Namespace and key travel together: a legacy free-form key cannot collide with Steam storage.
public struct CatalogPersonalizationReference: Codable, Equatable, Sendable {
    public let namespace: CatalogIntegration
    public let key: String
}

public enum CatalogModelError: Error, Equatable {
    case wrongIntegration, identityMismatch, invalidRecord, duplicateGameID, duplicateSteamAppID, duplicateInstallationID
    case unsupportedSchema(Int)
}

public enum CatalogInstallationAvailability: String, Codable, Sendable {
    case available, unavailable, requiresReview, notDetected, sourceUnavailable
}

public struct CatalogNativeApplication: Codable, Equatable, Sendable {
    public let url: URL
    public let executableURL: URL
    public let bundleIdentifier: String?
    public let name: String
    public let architectures: [MacExecutableArchitecture]
    public let isDeclaredGame: Bool

    public init(_ observed: NativeMacApplication) {
        url = observed.url
        executableURL = observed.executableURL
        bundleIdentifier = observed.bundleIdentifier
        name = observed.name
        architectures = observed.architectures.sorted { $0.rawValue < $1.rawValue }
        isDeclaredGame = observed.isDeclaredGame
    }
}

public struct SteamCatalogInstallation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var libraryURL: URL
    public var contentURL: URL
    public var applications: [CatalogNativeApplication]
    public var availability: CatalogInstallationAvailability
    public var reportedSizeBytes: Int64?
    public var buildID: String?
    public var lastObservedAt: Date

    public init(id: UUID = UUID(), libraryURL: URL, contentURL: URL, applications: [CatalogNativeApplication] = [],
                availability: CatalogInstallationAvailability = .requiresReview, reportedSizeBytes: Int64? = nil,
                buildID: String? = nil, lastObservedAt: Date = Date()) {
        self.id = id
        self.libraryURL = libraryURL
        self.contentURL = contentURL
        self.applications = applications
        self.availability = availability
        self.reportedSizeBytes = reportedSizeBytes
        self.buildID = buildID
        self.lastObservedAt = lastObservedAt
    }

    public var primaryApplication: CatalogNativeApplication? {
        let games = applications.filter(\.isDeclaredGame)
        return games.count == 1 ? games[0] : nil
    }
}

public struct SteamCatalogGame: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let appID: UInt32
    public var name: String
    public var isFavorite = false
    public var isHidden = false
    public var hasBeenRecognized = false
    /// Ambiguity survives missing/partial sources; only complete evidence clears it.
    public var needsInstallationReview = false
    public var installations: [SteamCatalogInstallation] = []

    public init(id: UUID = UUID(), appID: UInt32, name: String) { self.id = id; self.appID = appID; self.name = name }
}

/// One catalog entry, with one owner for each field. The old record remains a
/// lossless nxnative payload; a Steam entry never needs its build/settings defaults.
public struct CatalogGame: Identifiable, Codable, Equatable {
    enum Payload: Equatable { case nxnative(PortedGame), steam(SteamCatalogGame) }
    private(set) var payload: Payload
    public let personalizationReference: CatalogPersonalizationReference

    public init(nxnative game: PortedGame) {
        payload = .nxnative(game)
        personalizationReference = .init(namespace: .nxnative, key: game.titleId ?? game.uniqueKey)
    }

    public init(steam game: SteamCatalogGame) {
        payload = .steam(game)
        personalizationReference = .init(namespace: .steam, key: "steam-\(game.appID)")
    }

    public var integration: CatalogIntegration { if case .nxnative = payload { return .nxnative }; return .steam }
    public var id: UUID { switch payload { case .nxnative(let g): return g.id; case .steam(let g): return g.id } }
    public var name: String { switch payload { case .nxnative(let g): return g.name; case .steam(let g): return g.name } }
    public var isFavorite: Bool { switch payload { case .nxnative(let g): return g.isFavorite; case .steam(let g): return g.isFavorite } }
    public var isHidden: Bool { switch payload { case .nxnative(let g): return g.isHidden; case .steam(let g): return g.isHidden } }
    public var personalizationKey: String { personalizationReference.key }
    public var nxnativeGame: PortedGame? { if case .nxnative(let g) = payload { return g }; return nil }
    public var steamGame: SteamCatalogGame? { if case .steam(let g) = payload { return g }; return nil }

    public var providerIdentity: CatalogProviderIdentity {
        switch payload {
        case .nxnative(let game):
            let title = game.titleId.flatMap { $0.isEmpty ? nil : $0.uppercased() }
            return .init(integration: .nxnative, externalID: title ?? "legacy-\(game.id.uuidString.lowercased())")
        case .steam(let game): return .init(integration: .steam, externalID: String(game.appID))
        }
    }

    public mutating func setFavorite(_ value: Bool) {
        switch payload {
        case .nxnative(var game): game.isFavorite = value; payload = .nxnative(game)
        case .steam(var game): game.isFavorite = value; payload = .steam(game)
        }
    }

    public mutating func setHidden(_ value: Bool) {
        switch payload {
        case .nxnative(var game): game.isHidden = value; payload = .nxnative(game)
        case .steam(var game): game.isHidden = value; payload = .steam(game)
        }
    }

    public mutating func updateNXNative(_ game: PortedGame) throws {
        guard integration == .nxnative else { throw CatalogModelError.wrongIntegration }
        guard id == game.id else { throw CatalogModelError.identityMismatch }
        payload = .nxnative(game)
    }

    mutating func updateSteam(_ game: SteamCatalogGame) throws {
        guard let old = steamGame else { throw CatalogModelError.wrongIntegration }
        guard old.id == game.id, old.appID == game.appID else { throw CatalogModelError.identityMismatch }
        payload = .steam(game)
    }

    func validateRecord() throws {
        guard personalizationReference.namespace == integration, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CatalogModelError.invalidRecord
        }
        switch payload {
        case .nxnative(let game):
            guard game.url.isFileURL, game.sizeBytes >= 0 else { throw CatalogModelError.invalidRecord }
        case .steam(let game):
            guard game.appID > 0, personalizationKey == "steam-\(game.appID)" else { throw CatalogModelError.invalidRecord }
            var contentsByLibrary: [URL: Set<URL>] = [:]
            for installation in game.installations {
                guard contentsByLibrary[installation.libraryURL.standardizedFileURL, default: []]
                    .insert(installation.contentURL.standardizedFileURL).inserted else { throw CatalogModelError.invalidRecord }
                guard installation.libraryURL.isFileURL, installation.contentURL.isFileURL,
                      installation.reportedSizeBytes.map({ $0 >= 0 }) != false,
                      installation.applications.allSatisfy({ $0.url.isFileURL && $0.executableURL.isFileURL }) else {
                    throw CatalogModelError.invalidRecord
                }
                let common = installation.libraryURL.appendingPathComponent("steamapps/common").standardizedFileURL
                guard NativeMacApplication.isWithin(installation.contentURL.standardizedFileURL, root: common),
                      installation.contentURL.standardizedFileURL != common,
                      installation.applications.allSatisfy({
                          $0.url.pathExtension.lowercased() == "app" && !$0.architectures.isEmpty &&
                          NativeMacApplication.isWithin($0.url.standardizedFileURL, root: installation.contentURL.standardizedFileURL) &&
                          NativeMacApplication.isWithin($0.executableURL.standardizedFileURL, root: $0.url.standardizedFileURL)
                      }) else { throw CatalogModelError.invalidRecord }
                if installation.availability == .available, installation.primaryApplication == nil {
                    throw CatalogModelError.invalidRecord
                }
            }
        }
    }

    private enum CodingKeys: String, CodingKey { case integration, data, personalization }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(CatalogIntegration.self, forKey: .integration) {
        case .nxnative: payload = .nxnative(try c.decode(PortedGame.self, forKey: .data))
        case .steam: payload = .steam(try c.decode(SteamCatalogGame.self, forKey: .data))
        }
        personalizationReference = try c.decode(CatalogPersonalizationReference.self, forKey: .personalization)
        try validateRecord()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(integration, forKey: .integration)
        try c.encode(personalizationReference, forKey: .personalization)
        switch payload {
        case .nxnative(let game): try c.encode(game, forKey: .data)
        case .steam(let game): try c.encode(game, forKey: .data)
        }
    }
}
