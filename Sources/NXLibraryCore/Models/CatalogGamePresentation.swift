import Foundation

public enum CatalogLaunchTarget: Equatable, Sendable { case nxnative(appURL: URL), steam(appID: UInt32) }

public enum CatalogInstallationSize: Equatable, Sendable { case cached(Int64), steamReported(Int64), unknown }

public struct CatalogInstallationPresentation: Identifiable, Equatable, Sendable {
    public let id: String
    public let contentURL: URL
    public let applicationURL: URL?
    public let executableURL: URL?
    public let bundleIdentifier: String?
    public let availability: CatalogInstallationAvailability
    public let size: CatalogInstallationSize
}

/// A value projection. No engine service, filesystem probe or view initialization
/// is needed to decide which integration owns an operation.
public struct CatalogGamePresentation {
    public let id: UUID
    public let name: String
    public let integration: CatalogIntegration
    public let personalizationReference: CatalogPersonalizationReference
    public let isFavorite: Bool
    public let isHidden: Bool
    public let isListedNormally: Bool
    public let requiresReview: Bool
    public let installations: [CatalogInstallationPresentation]
    public let launchTarget: CatalogLaunchTarget?

    public init(game: CatalogGame, sourceEnabled: Bool) {
        id = game.id
        name = game.name
        integration = game.integration
        personalizationReference = game.personalizationReference
        isFavorite = game.isFavorite
        isHidden = game.isHidden
        switch game.payload {
        case .nxnative(let legacy):
            requiresReview = false
            isListedNormally = sourceEnabled && !legacy.isHidden
            launchTarget = sourceEnabled && legacy.isPlayableLocally ? .nxnative(appURL: legacy.url) : nil
            installations = legacy.url.pathExtension.lowercased() == "app" ? [
                .init(id: "nxnative-\(legacy.id.uuidString.lowercased())", contentURL: legacy.url, applicationURL: legacy.url,
                      executableURL: nil, bundleIdentifier: legacy.effectiveBundleId,
                      availability: legacy.isPlayableLocally ? .available : (legacy.status == .appMissing ? .notDetected : .unavailable),
                      size: .cached(legacy.sizeBytes))
            ] : []
        case .steam(let steam):
            requiresReview = !steam.hasBeenRecognized || steam.needsInstallationReview || steam.installations.contains { $0.availability == .requiresReview }
                || steam.installations.filter { $0.availability == .available }.count > 1
            isListedNormally = sourceEnabled && !steam.isHidden && steam.hasBeenRecognized
            let available = steam.installations.filter { $0.availability == .available && $0.primaryApplication != nil }
            launchTarget = sourceEnabled && steam.appID > 0 && steam.hasBeenRecognized && available.count == 1 && !requiresReview ? .steam(appID: steam.appID) : nil
            installations = steam.installations.map { installation in
                let app = installation.primaryApplication
                return .init(id: "steam-\(installation.id.uuidString.lowercased())", contentURL: installation.contentURL,
                             applicationURL: app?.url, executableURL: app?.executableURL, bundleIdentifier: app?.bundleIdentifier,
                             availability: installation.availability,
                             size: installation.reportedSizeBytes.map(CatalogInstallationSize.steamReported) ?? .unknown)
            }
        }
    }
}
