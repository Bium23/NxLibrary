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

    package init(id: String, contentURL: URL, applicationURL: URL?, executableURL: URL?, bundleIdentifier: String?,
                 availability: CatalogInstallationAvailability, size: CatalogInstallationSize) {
        self.id = id
        self.contentURL = contentURL
        self.applicationURL = applicationURL
        self.executableURL = executableURL
        self.bundleIdentifier = bundleIdentifier
        self.availability = availability
        self.size = size
    }
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
    /// A Steam game Steam is still installing: listed, never launched, not to review.
    public let isDownloading: Bool
    public let installations: [CatalogInstallationPresentation]
    public let launchTarget: CatalogLaunchTarget?

    public init(game: CatalogGame, sourceEnabled: Bool) {
        id = game.id
        name = game.name
        integration = game.integration
        personalizationReference = game.personalizationReference
        isFavorite = game.isFavorite
        isHidden = game.isHidden
        let presence = game.record.presence(sourceEnabled: sourceEnabled)
        requiresReview = presence.requiresReview
        isDownloading = presence.isDownloading
        isListedNormally = presence.isListedNormally
        launchTarget = presence.launchTarget
        installations = presence.installations
    }
}
