import Foundation

/// The integration that owns a catalog record, written as its name (`"steam"`, `"nxnative"`). An open value: a name
/// this version does not know still reads, and the catalog keeps that record (`CatalogDocument.preservedGames`).
public struct CatalogIntegration: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
    public var description: String { rawValue }

    public static let steam = Self(rawValue: "steam")
}

/// What the catalog needs from a source's game: who it is, the player's two flags, whether the record is sound, and
/// how it is present on this Mac. Steam's record (`SteamCatalogGame`) is in the base; a module adds its own.
public protocol CatalogSourceRecord: Codable, Equatable {
    static var integration: CatalogIntegration { get }
    var id: UUID { get }
    var name: String { get }
    var isFavorite: Bool { get set }
    var isHidden: Bool { get set }
    /// Throws `CatalogModelError.invalidRecord` for a record the catalog must not keep as it is.
    func validateRecord(personalizationKey: String) throws
    func presence(sourceEnabled: Bool) -> CatalogRecordPresence
    /// Installed on this Mac, for the library's Installed filter.
    var isInstalledForLibrary: Bool { get }
    /// Words a library search also matches besides the name.
    var librarySearchTerms: [String] { get }
}

extension CatalogSourceRecord {
    /// Records of different sources are never equal.
    func isEqual(to other: any CatalogSourceRecord) -> Bool { (other as? Self) == self }
}

/// How a record is present: what `CatalogGamePresentation` shows and whether Play can start it.
public struct CatalogRecordPresence: Equatable, Sendable {
    public var requiresReview: Bool
    public var isDownloading: Bool
    public var isListedNormally: Bool
    public var launchTarget: CatalogLaunchTarget?
    public var installations: [CatalogInstallationPresentation]

    public init(requiresReview: Bool, isDownloading: Bool, isListedNormally: Bool,
                launchTarget: CatalogLaunchTarget?, installations: [CatalogInstallationPresentation]) {
        self.requiresReview = requiresReview; self.isDownloading = isDownloading; self.isListedNormally = isListedNormally
        self.launchTarget = launchTarget; self.installations = installations
    }
}

/// The record types a catalog reader knows, given by whoever creates the store or the decoder (never a global list).
/// A record of any other integration is kept untouched.
public struct CatalogRecordKinds: @unchecked Sendable {
    public let types: [any CatalogSourceRecord.Type]
    public init(_ types: [any CatalogSourceRecord.Type]) { self.types = types }

    /// What the base knows by itself.
    public static let base = Self([SteamCatalogGame.self])
    /// Where a decoder carries the kinds (`JSONDecoder.userInfo`); without them a reader knows `base`.
    public static let userInfoKey = CodingUserInfoKey(rawValue: "arcane.catalogRecordKinds")!

    public func type(for integration: CatalogIntegration) -> (any CatalogSourceRecord.Type)? {
        types.first { $0.integration == integration }
    }
    public var integrations: [CatalogIntegration] { types.map { $0.integration } }

    static func of(_ decoder: Decoder) -> Self { decoder.userInfo[userInfoKey] as? Self ?? .base }

    /// A JSON decoder that reads these kinds.
    public func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.userInfo[Self.userInfoKey] = self
        return decoder
    }
}
