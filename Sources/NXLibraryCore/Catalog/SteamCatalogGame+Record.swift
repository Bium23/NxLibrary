import Foundation

/// Steam's record in the catalog: one AppID, its installations in Steam's libraries, Play through Steam.
extension SteamCatalogGame: CatalogSourceRecord {
    public static var integration: CatalogIntegration { .steam }

    /// The AppID is the personal key (`steam-<AppID>`); every installation lies inside its library's
    /// `steamapps/common`, and an available one has exactly one game app.
    public func validateRecord(personalizationKey: String) throws {
        guard appID > 0, personalizationKey == "steam-\(appID)" else { throw CatalogModelError.invalidRecord }
        var contentsByLibrary: [URL: Set<URL>] = [:]
        for installation in installations {
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

    public func presence(sourceEnabled: Bool) -> CatalogRecordPresence {
        let requiresReview = !isDownloading && (!hasBeenRecognized || needsInstallationReview
            || installations.contains { $0.availability == .requiresReview }
            || installations.filter { $0.availability == .available }.count > 1)
        let available = installations.filter { $0.availability == .available && $0.primaryApplication != nil }
        return CatalogRecordPresence(
            requiresReview: requiresReview,
            isDownloading: sourceEnabled && !isHidden && isDownloading,
            isListedNormally: sourceEnabled && !isHidden && (hasBeenRecognized || isDownloading),
            launchTarget: sourceEnabled && appID > 0 && hasBeenRecognized && available.count == 1 && !requiresReview ? .steam(appID: appID) : nil,
            installations: installations.map { installation in
                let app = installation.primaryApplication
                return .init(id: "steam-\(installation.id.uuidString.lowercased())", contentURL: installation.contentURL,
                             applicationURL: app?.url, executableURL: app?.executableURL, bundleIdentifier: app?.bundleIdentifier,
                             availability: installation.availability,
                             size: installation.reportedSizeBytes.map(CatalogInstallationSize.steamReported) ?? .unknown)
            })
    }

    public var isInstalledForLibrary: Bool {
        guard hasBeenRecognized else { return false }
        return installations.contains { $0.availability == .available || ($0.availability == .requiresReview && $0.primaryApplication != nil) }
    }

    public var librarySearchTerms: [String] {
        ["Steam", String(appID)] + installations.flatMap { $0.applications.compactMap(\.bundleIdentifier) }
    }
}
