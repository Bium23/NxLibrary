import XCTest
@testable import NXLibraryCore

final class SteamOptionsTests: XCTestCase {
    func testSteamMainRowsAreNxnativeCommonRowsInTheSameOrder() {
        let nx = GameOptionsPresentation(supportsRenderScale: false, isPlayable: true, sourcesDetached: false)
        for origin in [GameOptionsOrigin.spotlight, .collection] {
            let steam = SteamOptionsPresentation(canPlay: true, hasApp: true).focusableRows(level: .main, origin: origin)
            let shared = nx.focusableRows(level: .main, origin: origin).filter(steam.contains)
            XCTAssertEqual(steam, shared)
        }
        XCTAssertTrue(SteamOptionsPresentation(canPlay: true, hasApp: true).focusableRows(level: .main, origin: .spotlight).contains(.move))
        XCTAssertFalse(SteamOptionsPresentation(canPlay: true, hasApp: true).focusableRows(level: .main, origin: .collection).contains(.move))
    }

    func testSteamOptionsOfferNothingFromNxnative() {
        let p = SteamOptionsPresentation(canPlay: true, hasApp: true)
        let all = Set(p.focusableRows(level: .main, origin: .spotlight) + p.focusableRows(level: .editDetails, origin: .spotlight))
        XCTAssertTrue(all.isDisjoint(with: [.fullscreen, .frameRate, .consoleMode, .cheats, .mods, .openSaves, .rebuild,
                                            .attachSources, .openLog, .removeSources, .removeGame, .restoreDefaults]))
        XCTAssertEqual(p.focusableRows(level: .editDetails, origin: .collection), [.changeArtwork, .changeMetadata, .storePage])
        XCTAssertTrue(all.allSatisfy { p.about($0) != nil })
    }

    func testPlayAndFinderDimWithoutAnInstallation() {
        let missing = SteamOptionsPresentation(canPlay: false, hasApp: false)
        XCTAssertTrue(missing.isDimmed(.play))
        XCTAssertTrue(missing.isDimmed(.showInFinder))
        XCTAssertFalse(missing.isDimmed(.favorite))
        XCTAssertFalse(SteamOptionsPresentation(canPlay: true, hasApp: true).isDimmed(.play))
    }

    func testSteamArtworkPutsTheExactAppFirstWithoutRepeats() throws {
        let shot = try XCTUnwrap(URL(string: "https://shared.akamai.steamstatic.com/shot1.jpg"))
        let steamCover = SteamStoreArt.candidates(appID: 10, slot: .cover)
        let other = ArtworkCandidate(slot: .cover, source: "SteamGridDB", url: try XCTUnwrap(URL(string: "https://example.com/c.png")))
        let covers = ArtworkCandidates.steamList(for: .cover, appID: 10, screenshots: [shot],
                                                 online: [steamCover[0], other, ArtworkCandidate(slot: .logo, source: "x", url: shot)])
        XCTAssertEqual(covers.map(\.url), [steamCover[0].url, other.url])
        let backgrounds = ArtworkCandidates.steamList(for: .background, appID: 10, screenshots: [shot])
        XCTAssertEqual(backgrounds.map(\.source), ["Steam", "Steam screenshot 1"])
        XCTAssertTrue(ArtworkCandidates.steamList(for: .icon, appID: 10, screenshots: [shot]).isEmpty)
        XCTAssertTrue(ArtworkCandidates.steamList(for: .cover, appID: 0, screenshots: []).isEmpty)
    }
}
