import Foundation

public enum CatalogScanError: Error, Equatable { case sourceDisabled, staleScan, wrongSourceRoot, invalidSnapshot }

public struct CatalogScanTicket: Equatable, Sendable {
    public let revision: UUID
    public let rootURL: URL
    let configuredRootURL: URL
}

extension CatalogDocument {
    /// Capture this after committing source configuration, before starting I/O.
    public func steamScanTicket() throws -> CatalogScanTicket {
        try validate()
        guard let config = source(.steam), config.isEnabled, let root = config.rootURL else { throw CatalogScanError.sourceDisabled }
        return .init(revision: revision, rootURL: root.resolvingSymlinksInPath().standardizedFileURL,
                     configuredRootURL: root.standardizedFileURL)
    }
}

/// Pure reconciliation: no scans, game launches, settings writes or disk probes.
/// The caller commits the returned draft through CatalogStore's revision check.
public enum SteamCatalogReconciler {
    private struct InstallationKey: Hashable {
        let library: URL
        let content: URL
        init(_ library: URL, _ content: URL) {
            self.library = library.standardizedFileURL; self.content = content.standardizedFileURL
        }
    }

    public static func applying(_ snapshot: SteamLibrarySnapshot, ticket: CatalogScanTicket, to document: CatalogDocument,
                                observedAt: Date = Date()) throws -> CatalogDocument {
        try document.validate()
        guard let source = document.source(.steam), source.isEnabled, let root = source.rootURL else { throw CatalogScanError.sourceDisabled }
        guard document.revision == ticket.revision, root.standardizedFileURL == ticket.configuredRootURL else { throw CatalogScanError.staleScan }
        let libraries = snapshot.libraries.map { $0.root.standardizedFileURL }
        guard libraries.contains(ticket.rootURL) else { throw CatalogScanError.wrongSourceRoot }
        guard Set(libraries).count == libraries.count, libraries.allSatisfy(\.isFileURL) else { throw CatalogScanError.invalidSnapshot }
        let unreadable = Set(snapshot.libraries.filter { !$0.isReadable }.map { $0.root.standardizedFileURL })
        let grouped = Dictionary(grouping: snapshot.games, by: \.appID)
        for observation in snapshot.games {
            guard observation.appID > 0, libraries.contains(observation.libraryURL.standardizedFileURL),
                  !unreadable.contains(observation.libraryURL.standardizedFileURL) else { throw CatalogScanError.invalidSnapshot }
        }
        var result = document
        var indices = Dictionary(uniqueKeysWithValues: result.games.enumerated().compactMap { index, record in
            record.steamGame.map { ($0.appID, index) }
        })
        let seenByAppID = grouped.mapValues { Set($0.map { InstallationKey($0.libraryURL, $0.installationURL) }) }
        // Absence is meaningful only for a complete source. A source error can
        // report unavailability, but can never erase an entry or its identity.
        for index in result.games.indices {
            guard var game = result.games[index].steamGame else { continue }
            if game.installations.contains(where: { $0.availability == .requiresReview })
                || game.installations.filter({ $0.availability == .available }).count > 1 {
                game.needsInstallationReview = true
            }
            if snapshot.isComplete && grouped[game.appID] == nil { game.needsInstallationReview = false }
            for i in game.installations.indices {
                let installation = game.installations[i]
                let key = InstallationKey(installation.libraryURL, installation.contentURL)
                if seenByAppID[game.appID]?.contains(key) != true {
                    if unreadable.contains(key.library) { game.installations[i].availability = .sourceUnavailable }
                    else if snapshot.isComplete { game.installations[i].availability = .notDetected }
                }
            }
            try result.games[index].updateSteam(game)
        }
        for appID in grouped.keys.sorted() {
            let observations = grouped[appID]!.sorted {
                ($0.libraryURL.path, $0.installationURL.path) < ($1.libraryURL.path, $1.installationURL.path)
            }
            guard Set(observations.map { InstallationKey($0.libraryURL, $0.installationURL) }).count == observations.count else {
                throw CatalogScanError.invalidSnapshot
            }
            let index = indices[appID]
            var game = index.flatMap { result.games[$0].steamGame } ?? SteamCatalogGame(appID: appID, name: observations[0].name)
            game.name = observations[0].name
            var installs = Dictionary(uniqueKeysWithValues: game.installations.enumerated().map {
                (InstallationKey($0.element.libraryURL, $0.element.contentURL), $0.offset)
            })
            var observedAmbiguity = false
            for observed in observations {
                let key = InstallationKey(observed.libraryURL, observed.installationURL)
                let apps = observed.nativeApps.map(CatalogNativeApplication.init)
                let ready = observed.state == .nativeReady && apps.filter(\.isDeclaredGame).count == 1
                let availability: CatalogInstallationAvailability = observations.count > 1 ? .requiresReview
                    : (ready ? .available : (observed.state == .unavailable ? .unavailable : .requiresReview))
                if availability == .requiresReview { observedAmbiguity = true }
                if ready && observations.count == 1 { game.hasBeenRecognized = true }
                let installIndex = installs[key]
                let installation = SteamCatalogInstallation(id: installIndex.map { game.installations[$0].id } ?? UUID(),
                    libraryURL: key.library, contentURL: key.content, applications: apps, availability: availability,
                    reportedSizeBytes: observed.reportedSizeBytes, buildID: observed.buildID, lastObservedAt: observedAt)
                if let installIndex { game.installations[installIndex] = installation }
                else { installs[key] = game.installations.count; game.installations.append(installation) }
            }
            if observedAmbiguity { game.needsInstallationReview = true }
            else if snapshot.isComplete { game.needsInstallationReview = false }
            if let index { try result.games[index].updateSteam(game) }
            else { indices[appID] = result.games.count; result.games.append(.init(steam: game)) }
        }
        try result.validate()
        return result
    }
}
