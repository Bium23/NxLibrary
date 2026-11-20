import Foundation

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
    /// Steam has not finished installing it (no FullyInstalled flag); `availability` stays `.unavailable`.
    /// A separate key, not an availability case, so a catalog written now still loads in an older NX Library.
    public var isDownloading: Bool

    public init(id: UUID = UUID(), libraryURL: URL, contentURL: URL, applications: [CatalogNativeApplication] = [],
                availability: CatalogInstallationAvailability = .requiresReview, reportedSizeBytes: Int64? = nil,
                buildID: String? = nil, lastObservedAt: Date = Date(), isDownloading: Bool = false) {
        self.isDownloading = isDownloading
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

    private enum CodingKeys: String, CodingKey {
        case id, libraryURL, contentURL, applications, availability, reportedSizeBytes, buildID, lastObservedAt, isDownloading
    }

    /// Catalogs written before downloads were tracked have no `isDownloading`: not downloading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        libraryURL = try c.decode(URL.self, forKey: .libraryURL)
        contentURL = try c.decode(URL.self, forKey: .contentURL)
        applications = try c.decode([CatalogNativeApplication].self, forKey: .applications)
        availability = try c.decode(CatalogInstallationAvailability.self, forKey: .availability)
        reportedSizeBytes = try c.decodeIfPresent(Int64.self, forKey: .reportedSizeBytes)
        buildID = try c.decodeIfPresent(String.self, forKey: .buildID)
        lastObservedAt = try c.decode(Date.self, forKey: .lastObservedAt)
        isDownloading = try c.decodeIfPresent(Bool.self, forKey: .isDownloading) ?? false
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

    /// Descriptive lookup in catalog order, shared by artwork, facts and process observation.
    /// Play separately checks source status, review and installation uniqueness in `CatalogGamePresentation`.
    public var firstAvailableInstallation: SteamCatalogInstallation? {
        installations.first { $0.availability == .available }
    }

    /// Steam is installing it: of the installations still detected, the only one is downloading. An old folder no
    /// longer detected (a game removed and installed again elsewhere) does not hide the download.
    public var isDownloading: Bool {
        let detected = installations.filter { $0.availability != .notDetected }
        return detected.count == 1 && detected[0].isDownloading
    }

    /// For Settings → Steam's "to review": never recognized or ambiguous, and not simply still downloading.
    public var needsReview: Bool { !isDownloading && (!hasBeenRecognized || needsInstallationReview) }
}

/// One catalog entry, with one owner for each field. The record is the source's own value, kept whole: the complete
/// nxnative record for a ported game, `SteamCatalogGame` for Steam; a Steam entry never needs build or settings defaults.
public struct CatalogGame: Identifiable, Codable, Equatable {
    public private(set) var record: any CatalogSourceRecord
    public let personalizationReference: CatalogPersonalizationReference

    public init(record: some CatalogSourceRecord, personalizationKey: String) {
        self.record = record
        personalizationReference = .init(namespace: type(of: record).integration, key: personalizationKey)
    }

    public init(steam game: SteamCatalogGame) { self.init(record: game, personalizationKey: "steam-\(game.appID)") }

    public var integration: CatalogIntegration { type(of: record).integration }
    public var id: UUID { record.id }
    public var name: String { record.name }
    public var isFavorite: Bool { record.isFavorite }
    public var isHidden: Bool { record.isHidden }
    public var personalizationKey: String { personalizationReference.key }
    public var steamGame: SteamCatalogGame? { record as? SteamCatalogGame }

    public mutating func setFavorite(_ value: Bool) { record.isFavorite = value }
    public mutating func setHidden(_ value: Bool) { record.isHidden = value }

    /// Replaces the record with a newer one of the same source and game.
    public mutating func replaceRecord<Record: CatalogSourceRecord>(_ updated: Record) throws {
        guard record is Record else { throw CatalogModelError.wrongIntegration }
        guard id == updated.id else { throw CatalogModelError.identityMismatch }
        record = updated
    }

    mutating func updateSteam(_ game: SteamCatalogGame) throws {
        guard let old = steamGame else { throw CatalogModelError.wrongIntegration }
        guard old.appID == game.appID else { throw CatalogModelError.identityMismatch }
        try replaceRecord(game)
    }

    func validateRecord() throws {
        guard personalizationReference.namespace == integration, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CatalogModelError.invalidRecord
        }
        try record.validateRecord(personalizationKey: personalizationKey)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.personalizationReference == rhs.personalizationReference && lhs.record.isEqual(to: rhs.record)
    }

    private enum CodingKeys: String, CodingKey { case integration, data, personalization }
    /// Reads a record of a kind the decoder knows (`CatalogRecordKinds`); any other integration is refused here and
    /// kept by `CatalogDocument`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let integration = try c.decode(CatalogIntegration.self, forKey: .integration)
        guard let kind = CatalogRecordKinds.of(decoder).type(for: integration) else {
            throw DecodingError.dataCorruptedError(forKey: .integration, in: c, debugDescription: "Unknown integration \(integration)")
        }
        record = try c.decode(kind, forKey: .data)
        personalizationReference = try c.decode(CatalogPersonalizationReference.self, forKey: .personalization)
        try validateRecord()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(integration, forKey: .integration)
        try c.encode(personalizationReference, forKey: .personalization)
        try c.encode(record, forKey: .data)
    }
}
