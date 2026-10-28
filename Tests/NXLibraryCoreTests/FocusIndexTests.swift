import XCTest
@testable import NXLibraryCore

final class FocusIndexTests: XCTestCase {
    func testMoveClamps() {
        var focus = FocusIndex(index: 0)
        focus.move(by: 1, count: 3)
        XCTAssertEqual(focus.index, 1)
        focus.move(by: 10, count: 3)
        XCTAssertEqual(focus.index, 2)
        focus.move(by: -10, count: 3)
        XCTAssertEqual(focus.index, 0)
    }

    func testEmptyCountKeepsZero() {
        var focus = FocusIndex(index: 2)
        focus.move(by: 1, count: 0)
        XCTAssertEqual(focus.index, 0)
    }
}
