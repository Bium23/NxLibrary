import XCTest
@testable import NXLibraryCore

/// NX Library comes back after a Steam game only when Play came from NX Library, the game was the app in front
/// and no other library game is still open.
final class SteamReturnFocusTests: XCTestCase {
    private let id = UUID()

    func testPlayedHereInFrontAndAloneComesBack() {
        var focus = SteamReturnFocus()
        focus.playPressed(id)
        focus.gameCameForward(id)
        XCTAssertTrue(focus.gameEnded(id, othersRunning: false))
    }

    func testStartedFromSteamDoesNotComeBack() {
        var focus = SteamReturnFocus()
        focus.gameCameForward(id)
        XCTAssertFalse(focus.gameEnded(id, othersRunning: false))
    }

    func testLeavingTheGameForAnotherAppDoesNotComeBack() {
        var focus = SteamReturnFocus()
        focus.playPressed(id)
        focus.gameCameForward(id)
        focus.otherAppStayedForward(whileRunning: id)
        XCTAssertFalse(focus.gameEnded(id, othersRunning: false))
    }

    func testAnotherOpenGameKeepsNXLibraryBack() {
        var focus = SteamReturnFocus()
        focus.playPressed(id)
        focus.gameCameForward(id)
        XCTAssertFalse(focus.gameEnded(id, othersRunning: true))
    }

    func testAnAbandonedPlayDoesNotCountLater() {
        var focus = SteamReturnFocus()
        focus.playPressed(id)
        focus.playAbandoned(id)
        focus.gameCameForward(id)
        XCTAssertFalse(focus.gameEnded(id, othersRunning: false))
    }

    func testEachPlayCountsOnce() {
        var focus = SteamReturnFocus()
        focus.playPressed(id)
        focus.gameCameForward(id)
        XCTAssertTrue(focus.gameEnded(id, othersRunning: false))
        focus.gameCameForward(id)
        XCTAssertFalse(focus.gameEnded(id, othersRunning: false), "a later start from Steam is not NX Library's")
    }
}
