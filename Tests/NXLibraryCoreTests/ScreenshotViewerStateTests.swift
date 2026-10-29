import XCTest
@testable import NXLibraryCore

final class ScreenshotViewerStateTests: XCTestCase {
    func testStartIsClamped() {
        XCTAssertEqual(ScreenshotViewerState(count: 6, start: 9).index, 5)
        XCTAssertEqual(ScreenshotViewerState(count: 6, start: -2).index, 0)
        XCTAssertEqual(ScreenshotViewerState(count: 0, start: 3).index, 0)
    }

    func testPagingClampsAtEnds() {
        var state = ScreenshotViewerState(count: 3)
        XCTAssertFalse(state.previous())
        XCTAssertEqual(state.index, 0)
        XCTAssertTrue(state.next())
        XCTAssertTrue(state.next())
        XCTAssertFalse(state.next())
        XCTAssertEqual(state.index, 2)
    }

    func testLabelIsOneBased() {
        XCTAssertEqual(ScreenshotViewerState(count: 6, start: 2).label, "3 / 6")
        XCTAssertEqual(ScreenshotViewerState(count: 0).label, "")
    }

    func testEmptyNeverMoves() {
        var state = ScreenshotViewerState(count: 0)
        XCTAssertFalse(state.next())
        XCTAssertFalse(state.previous())
    }
}
