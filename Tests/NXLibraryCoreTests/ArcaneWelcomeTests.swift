import XCTest
@testable import NXLibraryCore

final class ArcaneWelcomeTests: XCTestCase {
    func testShowsOnceAfterUpdate() {
        XCTAssertTrue(ArcaneWelcome.shouldShow(setupCompleted: true, shown: false, hasPendingRecovery: false))
        XCTAssertFalse(ArcaneWelcome.shouldShow(setupCompleted: true, shown: true, hasPendingRecovery: false))
    }

    func testUnfinishedSetupNeverShows() {
        XCTAssertFalse(ArcaneWelcome.shouldShow(setupCompleted: false, shown: false, hasPendingRecovery: false))
    }

    func testNewInstallNeverShows() {
        let finished = ArcaneWelcome.markShown(AppSettings())
        XCTAssertTrue(finished.welcomeArcaneShown)
        XCTAssertFalse(ArcaneWelcome.shouldShow(setupCompleted: true, shown: finished.welcomeArcaneShown,
                                                hasPendingRecovery: false))
    }

    func testWaitsForPendingRecovery() {
        XCTAssertFalse(ArcaneWelcome.shouldShow(setupCompleted: true, shown: false, hasPendingRecovery: true))
    }

    func testOldSettingsFileDecodesAsNotShown() throws {
        let old = Data(#"{"showClock": false}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertFalse(settings.welcomeArcaneShown)
        XCTAssertFalse(settings.showClock)
        var shown = settings
        shown.welcomeArcaneShown = true
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(shown))
        XCTAssertTrue(back.welcomeArcaneShown)
    }

    func testOfferOnlyWhenSteamFoundAndOff() {
        XCTAssertEqual(ArcaneWelcome.offer(steamEnabled: false, steamGameCount: 12), .steam(gameCount: 12))
        XCTAssertNil(ArcaneWelcome.offer(steamEnabled: true, steamGameCount: 12))
        XCTAssertNil(ArcaneWelcome.offer(steamEnabled: false, steamGameCount: 0))
        XCTAssertNil(ArcaneWelcome.offer(steamEnabled: false, steamGameCount: nil))
    }

    func testFocusOrder() {
        let offer = ArcaneWelcome.Offer.steam(gameCount: 3)
        XCTAssertEqual(ArcaneWelcome.Focus.order(offer: offer), [.add, .notNow, .openLibrary])
        XCTAssertEqual(ArcaneWelcome.Focus.order(offer: nil), [.openLibrary])
        XCTAssertEqual(ArcaneWelcome.Focus.initial(offer: offer), .add)
        XCTAssertEqual(ArcaneWelcome.Focus.initial(offer: nil), .openLibrary)
        XCTAssertEqual(ArcaneWelcome.Focus.add.moved(.right, offer: offer), .notNow)
        XCTAssertEqual(ArcaneWelcome.Focus.notNow.moved(.left, offer: offer), .add)
        XCTAssertEqual(ArcaneWelcome.Focus.add.moved(.down, offer: offer), .openLibrary)
        XCTAssertEqual(ArcaneWelcome.Focus.notNow.moved(.down, offer: offer), .openLibrary)
        XCTAssertEqual(ArcaneWelcome.Focus.openLibrary.moved(.up, offer: offer), .add)
        XCTAssertEqual(ArcaneWelcome.Focus.openLibrary.moved(.up, offer: nil), .openLibrary)
        XCTAssertEqual(ArcaneWelcome.Focus.add.moved(.up, offer: offer), .add)
    }

    func testDismissingMarksShown() {
        for exit in ArcaneWelcome.Exit.allCases {
            XCTAssertTrue(ArcaneWelcome.settings(after: exit, from: AppSettings()).welcomeArcaneShown, "\(exit)")
        }
    }
}
