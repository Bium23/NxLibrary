import XCTest
@testable import NXLibraryCore

final class GameFocusTests: XCTestCase {
    private let zelda = "org.nxnative.zelda"
    private let mario = "org.nxnative.mario"

    func testAGameThatQuitsInFrontBringsTheLibraryBack() {
        var focus = GameFocus()
        focus.gameCameForward(zelda)
        XCTAssertTrue(focus.gameEnded(zelda, othersRunning: false))
    }

    func testAGameNeverInFrontDoesNot() {
        var focus = GameFocus()
        XCTAssertFalse(focus.gameEnded(zelda, othersRunning: false))
    }

    func testAGameLeftForAnotherAppDoesNot() {
        var focus = GameFocus()
        focus.gameCameForward(zelda)
        focus.otherAppStayedForward(whileRunning: zelda)
        XCTAssertFalse(focus.gameEnded(zelda, othersRunning: false))
    }

    func testAnotherGameStillOpenKeepsTheLibraryBehind() {
        var focus = GameFocus()
        focus.gameCameForward(zelda)
        XCTAssertFalse(focus.gameEnded(zelda, othersRunning: true))
    }

    func testOnlyTheGameInFrontCounts() {
        var focus = GameFocus()
        focus.gameCameForward(zelda)
        focus.gameCameForward(mario)
        XCTAssertFalse(focus.gameEnded(zelda, othersRunning: true))
        XCTAssertTrue(focus.gameEnded(mario, othersRunning: false))
    }

    func testLeavingAnotherGameKeepsTheOneInFront() {
        var focus = GameFocus()
        focus.gameCameForward(zelda)
        focus.otherAppStayedForward(whileRunning: mario)
        XCTAssertTrue(focus.gameEnded(zelda, othersRunning: false))
    }

    func testAQuitIsCountedOnce() {
        var focus = GameFocus()
        focus.gameCameForward(zelda)
        XCTAssertTrue(focus.gameEnded(zelda, othersRunning: false))
        XCTAssertFalse(focus.gameEnded(zelda, othersRunning: false))
    }
}
