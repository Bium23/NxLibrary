import XCTest
@testable import NXLibraryCore

final class AchievementsScreenStateTests: XCTestCase {
    private func ids(_ count: Int) -> [String] { (0..<count).map { "A\($0)" } }

    func testMovesInOneColumn() {
        var state = AchievementsScreenState(ids: ids(3))
        XCTAssertTrue(state.move(.down))
        XCTAssertEqual(state.index, 1)
        XCTAssertTrue(state.move(.down))
        XCTAssertEqual(state.index, 2)
        XCTAssertFalse(state.move(.down), "no row below the last")
        XCTAssertTrue(state.move(.up))
        XCTAssertEqual(state.index, 1)
        state.index = 0
        XCTAssertFalse(state.move(.up))
    }

    func testLeftRightNeverMove() {
        var state = AchievementsScreenState(ids: ids(4))
        state.index = 1
        XCTAssertFalse(state.move(.left))
        XCTAssertFalse(state.move(.right))
        XCTAssertEqual(state.index, 1)
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
        XCTAssertEqual(state.filter, .locked)
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

    // MARK: - Detail (A opens the focused achievement)

    func testDetailOpensOnTheFocusedRow() {
        var state = AchievementsScreenState(ids: ids(3))
        state.index = 1
        XCTAssertTrue(state.openDetail())
        XCTAssertTrue(state.isDetailOpen)
        XCTAssertEqual(state.focusedID, "A1")
        state.closeDetail()
        XCTAssertFalse(state.isDetailOpen)
        XCTAssertEqual(state.index, 1, "closing keeps the row")
    }

    func testDetailNeedsARow() {
        var state = AchievementsScreenState(ids: [])
        XCTAssertFalse(state.openDetail())
        XCTAssertFalse(state.isDetailOpen)
    }

    func testMovingWhileOpenStepsTheDetail() {
        var state = AchievementsScreenState(ids: ids(3))
        state.openDetail()
        XCTAssertTrue(state.move(.down))
        XCTAssertTrue(state.isDetailOpen)
        XCTAssertEqual(state.focusedID, "A1")
    }

    func testFilterClosesTheDetail() {
        var state = AchievementsScreenState(ids: ids(3))
        state.openDetail()
        state.setFilter(.locked, ids: ids(2))
        XCTAssertFalse(state.isDetailOpen)
        state.openDetail()
        state.shiftFilter(by: 1) { _ in self.ids(2) }
        XCTAssertFalse(state.isDetailOpen)
    }

    /// A re-read keeps the detail on its achievement; gone from the list, the detail closes rather than show
    /// another one.
    func testRereadKeepsOrClosesTheDetail() {
        var state = AchievementsScreenState(ids: ids(3))
        state.index = 1
        state.openDetail()
        state.setIDs(["A9", "A1", "A2"])
        XCTAssertTrue(state.isDetailOpen)
        XCTAssertEqual(state.focusedID, "A1")
        state.setIDs(["A0", "A2"])
        XCTAssertFalse(state.isDetailOpen)
    }

    // MARK: - Order (Y)

    func testOrderCyclesAndStartsAtTheTop() {
        var state = AchievementsScreenState(ids: ids(4))
        XCTAssertEqual(state.order, .default)
        state.index = 3
        state.cycleOrder { _ in self.ids(4) }
        XCTAssertEqual(state.order, .rarest)
        XCTAssertEqual(state.index, 0)
        state.cycleOrder { _ in self.ids(4) }
        XCTAssertEqual(state.order, .commonest)
        state.cycleOrder { _ in self.ids(4) }
        XCTAssertEqual(state.order, .default, "wraps")
    }

    func testOrderPassesItselfForTheRows() {
        var state = AchievementsScreenState(ids: ids(2))
        state.cycleOrder { $0 == .rarest ? ["R"] : [] }
        XCTAssertEqual(state.ids, ["R"])
    }

    func testFilterKeepsTheOrder() {
        var state = AchievementsScreenState(ids: ids(3))
        state.cycleOrder { _ in self.ids(3) }
        state.setFilter(.locked, ids: ids(1))
        XCTAssertEqual(state.order, .rarest)
    }

    func testOrderClosesTheDetail() {
        var state = AchievementsScreenState(ids: ids(3))
        state.openDetail()
        state.cycleOrder { _ in self.ids(3) }
        XCTAssertFalse(state.isDetailOpen)
    }
}
