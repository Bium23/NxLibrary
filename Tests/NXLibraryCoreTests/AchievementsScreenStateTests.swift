import XCTest
@testable import NXLibraryCore

final class AchievementsScreenStateTests: XCTestCase {
    func testMovesInTwoColumns() {
        var state = AchievementsScreenState(count: 5)
        XCTAssertTrue(state.move(.right))
        XCTAssertEqual(state.index, 1)
        XCTAssertTrue(state.move(.down))
        XCTAssertEqual(state.index, 3)
        state.index = 2
        XCTAssertTrue(state.move(.down))
        XCTAssertEqual(state.index, 4)
        state.index = 3
        XCTAssertFalse(state.move(.down), "no row below the second column's last tile")
        XCTAssertEqual(state.index, 3)
        XCTAssertTrue(state.move(.up))
        XCTAssertEqual(state.index, 1)
        XCTAssertFalse(state.move(.up))
    }

    func testLeftAtFirstColumnStays() {
        var state = AchievementsScreenState(count: 4)
        state.index = 2
        XCTAssertFalse(state.move(.left))
        XCTAssertEqual(state.index, 2)
        state.index = 3
        XCTAssertFalse(state.move(.right))
        XCTAssertEqual(state.index, 3)
    }

    func testRightOnAShortLastRowStays() {
        var state = AchievementsScreenState(count: 3)
        state.index = 2
        XCTAssertFalse(state.move(.right))
        XCTAssertEqual(state.index, 2)
    }

    func testEmptyListDoesNotMove() {
        var state = AchievementsScreenState(count: 0)
        XCTAssertFalse(state.move(.down))
        XCTAssertFalse(state.move(.right))
        XCTAssertEqual(state.index, 0)
    }

    func testFilterResetsIndex() {
        var state = AchievementsScreenState(count: 6)
        state.index = 5
        state.setFilter(.locked, count: 2)
        XCTAssertEqual(state.filter, .locked)
        XCTAssertEqual(state.index, 0)
        XCTAssertEqual(state.count, 2)
    }

    func testShiftFilterWraps() {
        var state = AchievementsScreenState(count: 3)
        state.shiftFilter(by: -1) { _ in 3 }
        XCTAssertEqual(state.filter, .rarest)
        state.shiftFilter(by: 1) { _ in 3 }
        XCTAssertEqual(state.filter, .all)
        state.shiftFilter(by: 1) { $0 == .unlocked ? 1 : 3 }
        XCTAssertEqual(state.filter, .unlocked)
        XCTAssertEqual(state.count, 1)
    }

    func testFewerRowsKeepTheIndexInside() {
        var state = AchievementsScreenState(count: 6)
        state.index = 5
        state.setCount(3)
        XCTAssertEqual(state.index, 2)
        state.setCount(0)
        XCTAssertEqual(state.index, 0)
        state.setCount(4)
        XCTAssertEqual(state.index, 0)
    }
}
