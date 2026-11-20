import Foundation
import NXLibraryCore

extension CatalogIntegration {
    /// nxnative's ported games, the first records the catalog had.
    public static let nxnative = Self(rawValue: "nxnative")
}

extension CatalogRecordKinds {
    /// Every kind this app knows: ported games and Steam.
    public static let standard = Self([PortedGame.self, SteamCatalogGame.self])
}

/// A ported game in the catalog: the complete nxnative record, kept whole.
extension PortedGame: CatalogSourceRecord {
    public static var integration: CatalogIntegration { .nxnative }

    public func validateRecord(personalizationKey: String) throws {
        guard url.isFileURL, sizeBytes >= 0 else { throw CatalogModelError.invalidRecord }
    }

    /// Listed unless hidden; Play opens the app when it is there. Only a `.app` counts as an installation.
    public func presence(sourceEnabled: Bool) -> CatalogRecordPresence {
        CatalogRecordPresence(
            requiresReview: false,
            isDownloading: false,
            isListedNormally: sourceEnabled && !isHidden,
            launchTarget: sourceEnabled && isPlayableLocally ? .nxnative(appURL: url) : nil,
            installations: url.pathExtension.lowercased() == "app" ? [
                .init(id: "nxnative-\(id.uuidString.lowercased())", contentURL: url, applicationURL: url,
                      executableURL: nil, bundleIdentifier: effectiveBundleId,
                      availability: isPlayableLocally ? .available : (status == .appMissing ? .notDetected : .unavailable),
                      size: .cached(sizeBytes))
            ] : [])
    }

    public var isInstalledForLibrary: Bool { isPlayableLocally }
    public var librarySearchTerms: [String] { [titleId, bundleId].compactMap { $0 } }
}

extension CatalogGame {
    /// The personal key stays the title ID (or the old unique key), as before the catalog.
    public init(nxnative game: PortedGame) { self.init(record: game, personalizationKey: game.titleId ?? game.uniqueKey) }

    public var nxnativeGame: PortedGame? { record as? PortedGame }

    public mutating func updateNXNative(_ game: PortedGame) throws { try replaceRecord(game) }
}
