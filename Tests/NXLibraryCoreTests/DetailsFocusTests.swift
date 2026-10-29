import XCTest
@testable import NXLibraryCore

final class DetailsFocusTests: XCTestCase {
    private let all = DetailsFocus.Bands(screenshots: 3, actions: 4, more: 2)

    func testDownWalksTopThenBandsInOrder() {
        var focus = DetailsFocus()
        XCTAssertTrue(focus.down(in: all))
        XCTAssertEqual(focus.zone, DetailsFocus.screenshotsZone)
        XCTAssertTrue(focus.down(in: all))
        XCTAssertEqual(focus.zone, DetailsFocus.actionsZone)
        // Inside the grid Down goes to the next row first (4 actions: rows 0-1, 2-3).
        XCTAssertTrue(focus.down(in: all))
        XCTAssertEqual(focus.action, 2)
        XCTAssertEqual(focus.zone, DetailsFocus.actionsZone)
        XCTAssertTrue(focus.down(in: all))
        XCTAssertEqual(focus.zone, DetailsFocus.moreZone)
        XCTAssertFalse(focus.down(in: all))
        XCTAssertEqual(focus.zone, DetailsFocus.moreZone)
    }

    func testEmptyScreenshotsBandIsSkipped() {
        var focus = DetailsFocus()
        let bands = DetailsFocus.Bands(screenshots: 0, actions: 4, more: 0)
        XCTAssertTrue(focus.down(in: bands))
        XCTAssertEqual(focus.zone, DetailsFocus.actionsZone)
        XCTAssertTrue(focus.down(in: bands))
        XCTAssertEqual(focus.action, 2)
        XCTAssertFalse(focus.down(in: bands))
    }

    func testUpReturnsOneBandAndEndsAtTop() {
        var focus = DetailsFocus()
        focus.zone = DetailsFocus.moreZone
        XCTAssertTrue(focus.up(in: all))
        XCTAssertEqual(focus.zone, DetailsFocus.actionsZone)
        XCTAssertTrue(focus.up(in: all))
        XCTAssertEqual(focus.zone, DetailsFocus.screenshotsZone)
        XCTAssertTrue(focus.up(in: all))
        XCTAssertEqual(focus.zone, DetailsFocus.topZone)
        XCTAssertFalse(focus.up(in: all))
    }

    func testUpSkipsEmptyScreenshotsToTop() {
        var focus = DetailsFocus()
        focus.zone = DetailsFocus.actionsZone
        XCTAssertTrue(focus.up(in: DetailsFocus.Bands(screenshots: 0, actions: 4, more: 0)))
        XCTAssertEqual(focus.zone, DetailsFocus.topZone)
    }

    func testActionGridMovesAcrossColumnsAndRows() {
        var focus = DetailsFocus()
        focus.zone = DetailsFocus.actionsZone
        XCTAssertTrue(focus.right(in: all))
        XCTAssertEqual(focus.action, 1)
        XCTAssertFalse(focus.right(in: all))
        XCTAssertTrue(focus.left(in: all))
        XCTAssertEqual(focus.action, 0)
        XCTAssertTrue(focus.down(in: all))
        XCTAssertEqual(focus.action, 2)
        XCTAssertTrue(focus.up(in: all))
        XCTAssertEqual(focus.action, 0)
    }

    func testActionGridLeavesBandFromLastRow() {
        var focus = DetailsFocus()
        focus.zone = DetailsFocus.actionsZone
        focus.action = 3
        XCTAssertTrue(focus.down(in: all))
        XCTAssertEqual(focus.zone, DetailsFocus.moreZone)
        XCTAssertEqual(focus.action, 3)
    }

    func testRightStopsAtLastActionInOddGrid() {
        var focus = DetailsFocus()
        focus.zone = DetailsFocus.actionsZone
        focus.action = 2
        let bands = DetailsFocus.Bands(screenshots: 0, actions: 3, more: 0)
        XCTAssertFalse(focus.right(in: bands))
        XCTAssertEqual(focus.action, 2)
        XCTAssertFalse(focus.down(in: bands))
    }

    func testPillsMoveLeftAndRightOnTop() {
        var focus = DetailsFocus()
        XCTAssertTrue(focus.right(in: all))
        XCTAssertEqual(focus.pill, 1)
        XCTAssertFalse(focus.right(in: all))
        XCTAssertTrue(focus.left(in: all))
        XCTAssertEqual(focus.pill, 0)
        XCTAssertFalse(focus.left(in: all))
    }

    func testMoreLikeThisMovesAlongRow() {
        var focus = DetailsFocus()
        focus.zone = DetailsFocus.moreZone
        XCTAssertTrue(focus.right(in: all))
        XCTAssertEqual(focus.more, 1)
        XCTAssertFalse(focus.right(in: all))
    }

    func testSettleMovesOffABandThatVanished() {
        var focus = DetailsFocus()
        focus.zone = DetailsFocus.moreZone
        focus.more = 4
        focus.settle(in: DetailsFocus.Bands(screenshots: 0, actions: 4, more: 0))
        XCTAssertEqual(focus.zone, DetailsFocus.actionsZone)
        XCTAssertEqual(focus.more, 0)
    }

    func testSettleClampsIndexesToCounts() {
        var focus = DetailsFocus()
        focus.zone = DetailsFocus.screenshotsZone
        focus.shot = 5
        focus.action = 6
        focus.settle(in: DetailsFocus.Bands(screenshots: 2, actions: 3, more: 0))
        XCTAssertEqual(focus.shot, 1)
        XCTAssertEqual(focus.action, 2)
    }

    func testFocusSetsZoneAndIndexForPointer() {
        var focus = DetailsFocus()
        focus.focus(zone: DetailsFocus.screenshotsZone, index: 2, in: all)
        XCTAssertEqual(focus.zone, DetailsFocus.screenshotsZone)
        XCTAssertEqual(focus.shot, 2)
        focus.focus(zone: DetailsFocus.moreZone, index: 9, in: all)
        XCTAssertEqual(focus.more, 1)
    }
}
