import XCTest
@testable import NXLibraryCore

final class SharedGamePresentationTests: XCTestCase {
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
        XCTAssertEqual(result.console, "Mac")
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
        XCTAssertEqual(CatalogGameOptions.commonRows(for: .steam, origin: .spotlight),
                       CatalogGameOptions.commonRows(for: .nxnative, origin: .spotlight))
        XCTAssertTrue(CatalogGameOptions.commonRows(for: .steam, origin: .spotlight).contains(.move))
        XCTAssertFalse(CatalogGameOptions.commonRows(for: .steam, origin: .collection).contains(.move))
        let steam = Set(CatalogGameOptions.specificRows(for: .steam))
        XCTAssertTrue(steam.isDisjoint(with: [.fullscreen, .frameRate, .consoleMode, .rebuild, .openSaves, .removeSources]))
        XCTAssertTrue(CatalogGameOptions.specificRows(for: .nxnative).contains(.rebuild))
    }
}
