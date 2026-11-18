import XCTest
@testable import NXLibraryCore

final class GridListLayoutTests: XCTestCase {
    /// Two columns of 100-point rows, 20 apart, 6 above the first and 130 kept free after the last.
    private let layout = GridListLayout(columns: 2, rowHeight: 100, spacing: 20, topPad: 6, bottomRoom: 130)

    func testContentHeightCountsWholeLinesAndTheRoomAfterThem() {
        XCTAssertEqual(layout.lines(count: 5), 3)
        XCTAssertEqual(layout.contentHeight(count: 5), 6 + 3 * 100 + 2 * 20 + 130)
        XCTAssertEqual(layout.contentHeight(count: 0), 6 + 130)
    }

    func testAnIndexSitsOnItsLine() {
        XCTAssertEqual(layout.top(of: 0), 6)
        XCTAssertEqual(layout.top(of: 1), 6)
        XCTAssertEqual(layout.top(of: 4), 6 + 2 * 120)
    }

    func testRevealSpanKeepsMarginsAroundTheRow() {
        XCTAssertEqual(layout.revealSpan(of: 2, above: 40, below: 130), (126 - 40)...(226 + 130))
    }

    func testVisibleLinesCoverTheWindowAndABuffer() {
        // Offset 300, window 400: lines touching 300...700 are 2...5; a 120 buffer adds one each side.
        XCTAssertEqual(layout.visibleLines(count: 20, offset: 300, visible: 400, buffer: 120), 1...6)
        XCTAssertNil(layout.visibleLines(count: 0, offset: 0, visible: 400, buffer: 120))
        XCTAssertEqual(layout.visibleLines(count: 3, offset: 0, visible: 400, buffer: 120), 0...1)
    }

    func testAFocusLeftOutOfViewMovesToTheNearestVisibleLineInItsColumn() {
        // Window 300...700 with margins 40 / 130: lines whole inside 340...570 are line 3 (366...466) only.
        XCTAssertEqual(layout.nearestVisible(index: 1, count: 20, offset: 300, visible: 400, above: 40, below: 130), 7)
        XCTAssertEqual(layout.nearestVisible(index: 18, count: 20, offset: 300, visible: 400, above: 40, below: 130), 6)
        XCTAssertNil(layout.nearestVisible(index: 6, count: 20, offset: 300, visible: 400, above: 40, below: 130))
    }

    func testANarrowWindowKeepsTheFocus() {
        // No line fits whole between the margins: the focus stays and the next move reveals it.
        XCTAssertNil(layout.nearestVisible(index: 0, count: 20, offset: 900, visible: 150, above: 40, below: 130))
    }

    func testAFocusInViewUnderTheMarginsKeepsTheFocus() {
        // The first row at the top (6...106) sits under the top margin but in view: Up must not move the focus down.
        XCTAssertNil(layout.nearestVisible(index: 0, count: 20, offset: 0, visible: 400, above: 52, below: 130))
        // A row revealed against the margin, with rounding left in the offset, is in view too.
        XCTAssertNil(layout.nearestVisible(index: 6, count: 20, offset: 366 - 52 + 0.0001, visible: 400, above: 52, below: 130))
        // Half under the bottom fade, still in view.
        XCTAssertNil(layout.nearestVisible(index: 8, count: 20, offset: 0, visible: 600, above: 52, below: 130))
    }
}
