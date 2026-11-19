import XCTest
@testable import NXLibraryCore

final class SharedGamePresentationTests: XCTestCase {
    private func installation(_ name: String, availability: CatalogInstallationAvailability,
                              size: Int64) -> SteamCatalogInstallation {
        let root = URL(fileURLWithPath: "/Volumes/\(name)/Steam")
        let content = root.appendingPathComponent("steamapps/common/Fixture")
        let app = content.appendingPathComponent("Game.app")
        let native = CatalogNativeApplication(NativeMacApplication(
            url: app, executableURL: app.appendingPathComponent("Contents/MacOS/game"),
            bundleIdentifier: "test.\(name)", name: "Fixture", architectures: [.arm64],
            isDeclaredGame: true, fileObservations: []))
        return SteamCatalogInstallation(libraryURL: root, contentURL: content, applications: [native],
                                        availability: availability, reportedSizeBytes: size,
                                        lastObservedAt: Date(timeIntervalSince1970: 0))
    }

    func testSteamArtworkAndDetailsKeepFirstAvailableInCatalogOrderWhileAmbiguousPlayIsBlocked() {
        var steam = SteamCatalogGame(appID: 42, name: "Fixture")
        steam.hasBeenRecognized = true
        steam.installations = [installation("Old", availability: .notDetected, size: 1_000_000_000),
                               installation("First", availability: .available, size: 140_000_000_000),
                               installation("Second", availability: .available, size: 2_000_000_000)]
        let game = CatalogGame(steam: steam)
        let expected = "/Volumes/First/Steam/steamapps/common/Fixture/Game.app"
        XCTAssertEqual(SteamArtworkRequest(game: game, role: .square).application?.url.path, expected)
        let page = GameDetailPresentation(steamRecord: game, metadata: nil, totalPlaytime: 0, lastPlayed: nil)
        XCTAssertEqual(page.appPath, expected)
        let facts = DetailsFacts.steamGame(game, metadata: nil, volumeName: "First", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(facts.first { $0.kind == .size }?.value, "140 GB")
        let launch = CatalogGamePresentation(game: game, sourceEnabled: true)
        XCTAssertTrue(launch.requiresReview)
        XCTAssertNil(launch.launchTarget)
    }

    func testSteamArtworkAndDetailsIgnoreHistoricalAndUnavailableInstallations() {
        for availability in [CatalogInstallationAvailability.unavailable, .notDetected, .sourceUnavailable, .requiresReview] {
            var steam = SteamCatalogGame(appID: 42, name: "Fixture")
            steam.hasBeenRecognized = true
            steam.installations = [installation("Old", availability: availability, size: 140_000_000_000)]
            let game = CatalogGame(steam: steam)
            XCTAssertNil(SteamArtworkRequest(game: game, role: .square).application)
            let page = GameDetailPresentation(steamRecord: game, metadata: nil, totalPlaytime: 0, lastPlayed: nil)
            XCTAssertEqual(page.appPath, "")
            XCTAssertEqual(DetailsFacts.steamGame(game, metadata: nil, volumeName: "Old"), [])
            XCTAssertNil(CatalogGamePresentation(game: game, sourceEnabled: true).launchTarget)
        }
    }

    func testSteamPresentationKeepsIdentityPersonalOverridesAndHistory() throws {
        let body = Data("""
        {"10":{"success":true,"data":{"steam_appid":10,"short_description":"Store text","genres":[{"description":"Strategy"}],"publishers":["Studio"],"release_date":{"date":"23 mag 2023"}}}}
        """.utf8)
        let facts = try SteamMetadata.decode(body, appID: 10, language: "italian")
        let record = CatalogGame(steam: SteamCatalogGame(appID: 10, name: "Fixture"))
        let result = LibraryPresentation(game: record, steamMetadata: facts,
                                         overrides: [.description: "Personal", .genres: "Puzzle, Adventure"],
                                         totalPlaytime: 7200, lastPlayed: nil)
        XCTAssertEqual(result.title, "Fixture")
        XCTAssertEqual(result.platform, "Steam")
        XCTAssertEqual(result.console, "Steam")
        XCTAssertEqual(result.summary, "Personal")
        XCTAssertEqual(result.publisher, "Studio")
        XCTAssertEqual(result.releaseYear, "2023")
        XCTAssertEqual(result.genres.count, 2)
        XCTAssertEqual(result.playtime, "2h 0m")
        XCTAssertFalse(result.sourcesDetached)
    }
    func testNXDisplayRemainsEqualThroughCommonBoundary() {
        let game = CatalogTestSupport.completeLegacyGame()
        let direct = LibraryPresentation(game: game, metadata: nil, totalPlaytime: 100, lastPlayed: nil)
        let common = LibraryPresentation(game: CatalogGame(nxnative: game), steamMetadata: nil,
                                         totalPlaytime: 100, lastPlayed: nil)
        XCTAssertEqual(common, direct)
    }
    func testPersonalFieldsRemainVisibleWithoutRemoteMetadata() {
        let game = CatalogGame(steam: SteamCatalogGame(appID: 10, name: "Local title"))
        let result = LibraryPresentation(game: game, steamMetadata: nil, overrides: [.description: "Offline choice", .publisher: "Mine"],
                                         totalPlaytime: 0, lastPlayed: nil)
        XCTAssertEqual(result.summary, "Offline choice")
        XCTAssertEqual(result.publisher, "Mine")
        XCTAssertEqual(result.title, "Local title")
    }
    func testSquareRoleDoesNotUsePortraitArtwork() {
        XCTAssertEqual(LibraryArtworkRole.square.slot, .icon)
        XCTAssertEqual(LibraryArtworkRole.cover.slot, .cover)
        XCTAssertEqual(LibraryArtworkRole.hero.slot, .background)
        XCTAssertEqual(LibraryArtworkRole.logo.slot, .logo)
    }
    func testCommonOptionsHaveSameOrderAndSourceActionsStaySeparate() {
        XCTAssertEqual(CatalogGameOptions.commonRows(origin: .spotlight),
                       [.play, .editDetails, .move, .favorite, .hidden, .showInFinder])
        XCTAssertEqual(CatalogGameOptions.commonRows(origin: .collection),
                       [.play, .editDetails, .favorite, .hidden, .showInFinder])
        let options = SteamOptionsPresentation(canPlay: true, hasApp: true)
        let steam = Set([GameOptionsLevel.main, .editDetails].flatMap { level in
            options.entries(level: level, origin: .spotlight).compactMap { entry -> GameOptionsRow? in
                if case .row(let row) = entry { return row } else { return nil }
            }
        })
        XCTAssertTrue(steam.isDisjoint(with: [.fullscreen, .frameRate, .consoleMode, .rebuild, .openSaves, .removeSources,
                                              .cheats, .mods, .attachSources, .openLog]))
    }

    /// Offline, a Steam page can show the text of another language: it says which, as a Switch page does.
    func testSteamTextInAnotherLanguageCarriesItsNotice() throws {
        let body = Data(#"{"10":{"success":true,"data":{"steam_appid":10,"short_description":"中文的商店描述"}}}"#.utf8)
        let facts = try SteamMetadata.decode(body, appID: 10, language: "schinese")
        let record = CatalogGame(steam: SteamCatalogGame(appID: 10, name: "Fixture"))
        try XCTSkipIf(SteamMetadata.language(L10n.context.language) == "schinese")
        let page = GameDetailPresentation(steamRecord: record, metadata: facts, totalPlaytime: 0, lastPlayed: nil)
        XCTAssertEqual(page.descriptionLanguage, "zh")
        XCTAssertNotNil(page.descriptionLanguageNote)
        let chosen = GameDetailPresentation(steamRecord: record, metadata: facts, overrides: [.description: "Mine"],
                                            totalPlaytime: 0, lastPlayed: nil)
        XCTAssertEqual(chosen.descriptionLanguage, "custom")
        XCTAssertNil(chosen.descriptionLanguageNote)
    }

    func testSteamPagePresentationClaimsNothingFromNxnative() throws {
        let body = Data("""
        {"10":{"success":true,"data":{"steam_appid":10,"short_description":"Store text","genres":[{"description":"Strategy"}],"developers":["Dev Studio"],"publishers":["Studio"],"release_date":{"date":"23 mag 2023"}}}}
        """.utf8)
        let facts = try SteamMetadata.decode(body, appID: 10, language: "italian")
        let record = CatalogGame(steam: SteamCatalogGame(appID: 10, name: "Fixture"))
        let other = CatalogGame(steam: SteamCatalogGame(appID: 20, name: "Other"))
        let page = GameDetailPresentation(steamRecord: record, metadata: facts, overrides: [.publisher: "Mine"],
                                          totalPlaytime: 60, lastPlayed: nil,
                                          libraryGames: [record, other], playtimeByGame: [other.id: 120])
        XCTAssertEqual(page.console, "Steam")
        XCTAssertEqual(page.description, "Store text")
        XCTAssertEqual(page.released, "23 mag 2023")
        XCTAssertEqual(page.releaseYear, "2023")
        XCTAssertEqual(page.developerLine, "Dev Studio")
        XCTAssertEqual(page.publisher, "Mine")
        XCTAssertEqual(page.rank, "#2 of 2")
        XCTAssertEqual(page.storeURL?.absoluteString, "https://store.steampowered.com/app/10/")
        XCTAssertFalse(page.canPlay); XCTAssertFalse(page.canRebuild); XCTAssertFalse(page.sourcesDetached)
        XCTAssertEqual(page.savePath, ""); XCTAssertEqual(page.engineCommitShort, "—")
        // Facts delivered for another game never reach this page.
        let stray = GameDetailPresentation(steamRecord: other, metadata: facts, totalPlaytime: 0, lastPlayed: nil)
        XCTAssertEqual(stray.description, "")
        XCTAssertNil(stray.rank)
    }
}
