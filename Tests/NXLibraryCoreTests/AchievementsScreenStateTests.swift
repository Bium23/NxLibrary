import XCTest
@testable import NXLibraryCore

final class AchievementsScreenStateTests: XCTestCase {
    private func ids(_ count: Int) -> [String] { (0..<count).map { "A\($0)" } }

    func testMovesInTwoColumns() {
        var state = AchievementsScreenState(ids: ids(5))
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
        var state = AchievementsScreenState(ids: ids(4))
        state.index = 2
        XCTAssertFalse(state.move(.left))
        XCTAssertEqual(state.index, 2)
        state.index = 3
        XCTAssertFalse(state.move(.right))
        XCTAssertEqual(state.index, 3)
    }

    func testRightOnAShortLastRowStays() {
        var state = AchievementsScreenState(ids: ids(3))
        state.index = 2
        XCTAssertFalse(state.move(.right))
        XCTAssertEqual(state.index, 2)
    }

    func testEmptyListDoesNotMove() {
        var state = AchievementsScreenState(ids: ids(0))
        XCTAssertFalse(state.move(.down))
        XCTAssertFalse(state.move(.right))
        XCTAssertEqual(state.index, 0)
    }

    func testFilterResetsIndex() {
        var state = AchievementsScreenState(ids: ids(6))
        state.index = 5
        state.setFilter(.locked, ids: ids(2))
        XCTAssertEqual(state.filter, .locked)
        XCTAssertEqual(state.index, 0)
        XCTAssertEqual(state.count, 2)
    }

    func testShiftFilterWraps() {
        var state = AchievementsScreenState(ids: ids(3))
        state.shiftFilter(by: -1) { _ in self.ids(3) }
        XCTAssertEqual(state.filter, .rarest)
        state.shiftFilter(by: 1) { _ in self.ids(3) }
        XCTAssertEqual(state.filter, .all)
        state.shiftFilter(by: 1) { self.ids($0 == .unlocked ? 1 : 3) }
        XCTAssertEqual(state.filter, .unlocked)
        XCTAssertEqual(state.count, 1)
    }

    func testFewerRowsKeepTheIndexInside() {
        var state = AchievementsScreenState(ids: ids(6))
        state.index = 5
        state.setIDs(ids(3))
        XCTAssertEqual(state.index, 2)
        state.setIDs([])
        XCTAssertEqual(state.index, 0)
        state.setIDs(ids(4))
        XCTAssertEqual(state.index, 0)
    }

    func testAReorderedListKeepsTheFocusedAchievement() {
        var state = AchievementsScreenState(ids: ["A", "B", "C", "D"])
        state.index = 2
        XCTAssertEqual(state.focusedID, "C")
        // The rarity arrived (or an unlock moved a row): the same achievement keeps the focus.
        state.setIDs(["C", "A", "D", "B"])
        XCTAssertEqual(state.index, 0)
        XCTAssertEqual(state.focusedID, "C")
        // Gone from this filter: the place it had, inside the list.
        state.setIDs(["A", "D"])
        XCTAssertEqual(state.index, 0)
    }
}
