import XCTest
@testable import NXLibraryCore

/// Arcane comes back after a Steam game only when Play came from Arcane, the game was the app in front
/// and no other library game is still open.
final class SteamReturnFocusTests: XCTestCase {
    private let id = UUID()

    func testPlayedHereInFrontAndAloneComesBack() {
        var focus = SteamReturnFocus()
        focus.playPressed(id)
        focus.gameCameForward(id)
        XCTAssertTrue(focus.gameEnded(id, othersRunning: false).returnsToLibrary)
    }

    func testStartedFromSteamDoesNotComeBack() {
        var focus = SteamReturnFocus()
        focus.gameCameForward(id)
        XCTAssertFalse(focus.gameEnded(id, othersRunning: false).returnsToLibrary)
    }

    func testLeavingTheGameForAnotherAppDoesNotComeBack() {
        var focus = SteamReturnFocus()
        focus.playPressed(id)
        focus.gameCameForward(id)
        focus.otherAppStayedForward(whileRunning: id)
        XCTAssertFalse(focus.gameEnded(id, othersRunning: false).returnsToLibrary)
    }

    func testAnotherOpenGameKeepsNXLibraryBack() {
        var focus = SteamReturnFocus()
        focus.playPressed(id)
        focus.gameCameForward(id)
        XCTAssertFalse(focus.gameEnded(id, othersRunning: true).returnsToLibrary)
    }

    func testAnAbandonedPlayDoesNotCountLater() {
        var focus = SteamReturnFocus()
        focus.playPressed(id)
        focus.playAbandoned(id)
        focus.gameCameForward(id)
        XCTAssertFalse(focus.gameEnded(id, othersRunning: false).returnsToLibrary)
    }

    func testEachPlayCountsOnce() {
        var focus = SteamReturnFocus()
        focus.playPressed(id)
        focus.gameCameForward(id)
        XCTAssertTrue(focus.gameEnded(id, othersRunning: false).returnsToLibrary)
        focus.gameCameForward(id)
        XCTAssertFalse(focus.gameEnded(id, othersRunning: false).returnsToLibrary, "a later start from Steam is not Arcane's")
    }

    // MARK: - Whether the player was still in the game

    func testAGameInFrontAtQuitWasBeingPlayed() {
        var focus = SteamReturnFocus()
        focus.playPressed(id)
        focus.gameCameForward(id)
        XCTAssertTrue(focus.gameEnded(id, othersRunning: true).wasInFront, "true even when Arcane stays back")
    }

    func testAGameLeftForAnotherAppWasNotInFront() {
        var focus = SteamReturnFocus()
        focus.playPressed(id)
        focus.gameCameForward(id)
        focus.otherAppStayedForward(whileRunning: id)
        XCTAssertFalse(focus.gameEnded(id, othersRunning: false).wasInFront)
    }
}
