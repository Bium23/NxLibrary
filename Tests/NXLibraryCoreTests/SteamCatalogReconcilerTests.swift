import XCTest
@testable import NXLibraryCore

final class SteamCatalogReconcilerTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/catalog-steam")
    private let external = URL(fileURLWithPath: "/tmp/catalog-external")
    private let observedAt = Date(timeIntervalSince1970: 1000.125)

    private func catalog() -> CatalogDocument {
        CatalogDocument(sources: [.init(integration: .nxnative, isEnabled: true),
                                  .init(integration: .steam, isEnabled: true, rootURL: root)],
                        games: [.init(nxnative: CatalogTestSupport.completeLegacyGame())])
    }
    private func observation(_ id: UInt32 = 10, name: String = "Same name", library: URL? = nil,
                             directory: String = "Game", state: SteamGameObservation.State = .nativeReady,
                             size: Int64? = 100) throws -> SteamGameObservation {
        let library = library ?? root
        let content = library.appendingPathComponent("steamapps/common/" + directory)
        let app = content.appendingPathComponent("Game.app")
        let native = NativeMacApplication(url: app, executableURL: app.appendingPathComponent("Contents/MacOS/game"),
                                          bundleIdentifier: "test.game", name: name, architectures: [.arm64],
                                          isDeclaredGame: true, fileObservations: [])
        return .init(appID: id, name: name, installationURL: content,
                     libraryURL: library, reportedSizeBytes: size, buildID: "42", nativeApps: [native], state: state)
    }
    private func snapshot(_ games: [SteamGameObservation], complete: Bool = true,
                          libraries: [SteamLibraryObservation]? = nil) -> SteamLibrarySnapshot {
        .init(libraries: libraries ?? [.init(root: root, isReadable: true, isComplete: complete)], games: games,
              issues: complete ? [] : [.init(url: root, appID: nil, reason: .invalidManifest)])
    }
    private func apply(_ scan: SteamLibrarySnapshot, to document: CatalogDocument) throws -> CatalogDocument {
        try SteamCatalogReconciler.applying(scan, ticket: document.steamScanTicket(), to: document, observedAt: observedAt)
    }

    func testScansRequireEnabledSourceAndMatchingRevisionAndRoot() throws {
        var document = catalog()
        let ticket = try document.steamScanTicket()
        document.sources[1].isEnabled = false
        XCTAssertThrowsError(try document.steamScanTicket())
        XCTAssertThrowsError(try SteamCatalogReconciler.applying(snapshot([]), ticket: ticket, to: document))
        document = catalog(); document.revision = UUID()
        XCTAssertThrowsError(try SteamCatalogReconciler.applying(snapshot([]), ticket: ticket, to: document))
        document = catalog(); document.sources[1].rootURL = external
        XCTAssertThrowsError(try SteamCatalogReconciler.applying(snapshot([]), ticket: ticket, to: document))
        document = catalog()
        XCTAssertThrowsError(try apply(snapshot([], libraries: [.init(root: external, isReadable: true, isComplete: true)]), to: document))
    }

    func testIdenticalNamesAcrossSourcesAndAppIDsStaySeparate() throws {
        var first = try observation()
        first = .init(appID: first.appID, name: "Fixture Switch game", installationURL: first.installationURL,
                      libraryURL: first.libraryURL, reportedSizeBytes: 100, buildID: "42", nativeApps: first.nativeApps, state: .nativeReady)
        let original = catalog()
        let result = try apply(snapshot([first, observation(20, name: "Fixture Switch game")]), to: original)
        XCTAssertEqual(result.games.count, 3)
        XCTAssertEqual(Set(result.games.map(\.id)).count, 3)
        XCTAssertEqual(Set(result.games.compactMap { $0.steamGame?.appID }), [10, 20])
        XCTAssertEqual(result.games.filter { $0.integration == .steam }.map(\.personalizationKey), ["steam-10", "steam-20"])
        XCTAssertEqual(result.games[0].nxnativeGame, original.games[0].nxnativeGame)
    }

    func testRefreshKeepsUUIDInstallationIDAndPersonalChoicesWhileUpdatingObservations() throws {
        let game = try observation()
        var document = try apply(snapshot([game]), to: catalog())
        document.games[1].setFavorite(true); document.games[1].setHidden(true)
        let before = document.games[1]
        let renamed = SteamGameObservation(appID: 10, name: "New name", installationURL: game.installationURL,
                                          libraryURL: game.libraryURL, reportedSizeBytes: 200, buildID: "43", nativeApps: game.nativeApps, state: .nativeReady)
        let result = try apply(snapshot([renamed]), to: document)
        let after = result.games[1]
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(after.steamGame?.installations.first?.id, before.steamGame?.installations.first?.id)
        XCTAssertEqual(after.personalizationReference, before.personalizationReference)
        XCTAssertTrue(after.isFavorite); XCTAssertTrue(after.isHidden)
        XCTAssertEqual(after.name, "New name")
        XCTAssertEqual(after.steamGame?.installations.first?.reportedSizeBytes, 200)
        XCTAssertEqual(after.steamGame?.installations.first?.buildID, "43")
        XCTAssertEqual(after.steamGame?.installations.first?.lastObservedAt, observedAt)
        XCTAssertEqual(result.games[0], document.games[0])
        XCTAssertEqual(result.revision, document.revision, "Store alone assigns the committed revision")
    }

    func testDuplicateAppIDRetainsBothInstallationsAndRequiresReview() throws {
        let a = try observation(), b = try observation(library: external)
        let scan = snapshot([a, b], libraries: [.init(root: root, isReadable: true, isComplete: true), .init(root: external, isReadable: true, isComplete: true)])
        let result = try apply(scan, to: catalog())
        XCTAssertEqual(result.games.count, 2)
        XCTAssertEqual(result.games[1].steamGame?.installations.count, 2)
        XCTAssertNil(CatalogGamePresentation(game: result.games[1], sourceEnabled: true).launchTarget)
        XCTAssertTrue(CatalogGamePresentation(game: result.games[1], sourceEnabled: true).requiresReview)
        let repeated = try apply(scan, to: result)
        XCTAssertEqual(repeated.games[1].steamGame?.installations.map(\.id), result.games[1].steamGame?.installations.map(\.id))
    }

    func testCompleteAbsenceMarksNotDetectedWithoutDeletingGameOrHistoryIdentity() throws {
        let document = try apply(snapshot([observation()]), to: catalog())
        let result = try apply(snapshot([]), to: document)
        XCTAssertEqual(result.games.count, 2)
        XCTAssertEqual(result.games[1].id, document.games[1].id)
        XCTAssertEqual(result.games[1].steamGame?.installations.first?.availability, .notDetected)
        XCTAssertTrue(CatalogGamePresentation(game: result.games[1], sourceEnabled: true).isListedNormally)
        XCTAssertNil(CatalogGamePresentation(game: result.games[1], sourceEnabled: true).launchTarget)
    }

    func testPartialScanPreservesUnseenStateAndUnreadableLibraryIsExplicit() throws {
        let document = try apply(snapshot([observation()]), to: catalog())
        let partial = try apply(snapshot([], complete: false), to: document)
        XCTAssertEqual(partial.games, document.games)
        let unavailable = snapshot([], complete: false, libraries: [.init(root: root, isReadable: false, isComplete: false)])
        let missing = try apply(unavailable, to: document)
        XCTAssertEqual(missing.games[1].steamGame?.installations.first?.availability, .sourceUnavailable)
        XCTAssertEqual(missing.games[1].id, document.games[1].id)
        XCTAssertNil(CatalogGamePresentation(game: missing.games[1], sourceEnabled: true).launchTarget)
    }

    func testMovedInstallationKeepsGameIdentityAndOldObservation() throws {
        let document = try apply(snapshot([observation()]), to: catalog())
        let result = try apply(snapshot([observation(directory: "Moved")]), to: document)
        XCTAssertEqual(result.games[1].id, document.games[1].id)
        let installs = try XCTUnwrap(result.games[1].steamGame?.installations)
        XCTAssertEqual(installs.count, 2)
        XCTAssertEqual(installs[0].availability, .notDetected)
        XCTAssertEqual(installs[1].availability, .available)
        XCTAssertEqual(installs[0].id, document.games[1].steamGame?.installations[0].id)
        XCTAssertEqual(CatalogGamePresentation(game: result.games[1], sourceEnabled: true).launchTarget, .steam(appID: 10))
    }

    func testUnrecognizedCandidatesDoNotBecomeNormalGamesOrLaunchTargets() throws {
        for state: SteamGameObservation.State in [.unavailable, .requiresReview] {
            let result = try apply(snapshot([observation(state: state)]), to: catalog())
            let presentation = CatalogGamePresentation(game: result.games[1], sourceEnabled: true)
            XCTAssertFalse(presentation.isListedNormally)
            XCTAssertTrue(presentation.requiresReview)
            XCTAssertNil(presentation.launchTarget)
        }
    }

    func testSourceDisableHidesAndBlocksLaunchWithoutLosingRecords() throws {
        let document = try apply(snapshot([observation()]), to: catalog())
        let steam = CatalogGamePresentation(game: document.games[1], sourceEnabled: false)
        XCTAssertFalse(steam.isListedNormally)
        XCTAssertNil(steam.launchTarget)
    }

    func testInvalidAppIDAndUnlistedLibraryCannotBeAccepted() throws {
        XCTAssertThrowsError(try apply(snapshot([observation(0)]), to: catalog()))
        XCTAssertThrowsError(try apply(snapshot([observation(library: external)]), to: catalog()))
    }
    func testNativeApplicationOutsideObservedInstallationIsRejected() throws {
        let original = try observation()
        let unsafe = SteamGameObservation(appID: 10, name: original.name,
                                          installationURL: external.appendingPathComponent("Outside"), libraryURL: root,
                                          reportedSizeBytes: nil, buildID: nil, nativeApps: original.nativeApps, state: .nativeReady)
        XCTAssertThrowsError(try apply(snapshot([unsafe]), to: catalog()))
    }

    func testDifferentAppIDReusingAPathDoesNotKeepMissingOldGameAvailable() throws {
        let document = try apply(snapshot([observation(10)]), to: catalog())
        let result = try apply(snapshot([observation(20)]), to: document)
        XCTAssertEqual(result.games[1].steamGame?.appID, 10)
        XCTAssertEqual(result.games[1].steamGame?.installations.first?.availability, .notDetected)
        XCTAssertNil(CatalogGamePresentation(game: result.games[1], sourceEnabled: true).launchTarget)
    }

    func testDuplicateInstallationPathsAreRejectedBeforeReconciliation() throws {
        var document = try apply(snapshot([observation()]), to: catalog())
        var game = try XCTUnwrap(document.games[1].steamGame)
        let original = game.installations[0]
        game.installations.append(.init(libraryURL: original.libraryURL, contentURL: original.contentURL,
                                       applications: original.applications, availability: .available))
        try document.games[1].updateSteam(game)
        XCTAssertThrowsError(try document.validate())
    }

    func testMissingDiskCannotResolveDuplicateAmbiguityAndReconnectRemainsBlocked() throws {
        let a = try observation(), b = try observation(library: external)
        let both = snapshot([a, b], libraries: [.init(root: root, isReadable: true, isComplete: true),
                                               .init(root: external, isReadable: true, isComplete: true)])
        let duplicate = try apply(both, to: catalog())
        let absentDisk = snapshot([a], complete: false, libraries: [.init(root: root, isReadable: true, isComplete: true),
                                                                 .init(root: external, isReadable: false, isComplete: false)])
        let partial = try apply(absentDisk, to: duplicate)
        let shown = CatalogGamePresentation(game: partial.games[1], sourceEnabled: true)
        XCTAssertTrue(shown.requiresReview)
        XCTAssertNil(shown.launchTarget)
        XCTAssertEqual(partial.games[1].steamGame?.installations.first { $0.libraryURL == external }?.availability, .sourceUnavailable)
        let reloaded = try JSONDecoder().decode(CatalogDocument.self, from: JSONEncoder().encode(partial))
        XCTAssertTrue(CatalogGamePresentation(game: reloaded.games[1], sourceEnabled: true).requiresReview)
        let reconnected = try apply(both, to: reloaded)
        XCTAssertTrue(CatalogGamePresentation(game: reconnected.games[1], sourceEnabled: true).requiresReview)
        XCTAssertNil(CatalogGamePresentation(game: reconnected.games[1], sourceEnabled: true).launchTarget)
        // Only complete evidence of one remaining installation resolves it.
        let resolved = try apply(snapshot([a], libraries: [.init(root: root, isReadable: true, isComplete: true),
                                                         .init(root: external, isReadable: true, isComplete: true)]), to: reconnected)
        XCTAssertFalse(CatalogGamePresentation(game: resolved.games[1], sourceEnabled: true).requiresReview)
        XCTAssertEqual(CatalogGamePresentation(game: resolved.games[1], sourceEnabled: true).launchTarget, .steam(appID: 10))
        XCTAssertEqual(resolved.games[1].id, duplicate.games[1].id)
    }

}
