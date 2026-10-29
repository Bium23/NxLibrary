import XCTest
@testable import NXLibraryCore

final class SpotlightStateTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    private var items: [SpotlightItem] {
        [.card(.surprise), .card(.addGame), .game(a), .game(b), .game(c)]
    }

    func testReconcilePrefersRestoredGameThenFirstGame() {
        var state = SpotlightState()
        state.reconcile(with: items, preferredGameID: b)
        XCTAssertEqual(state.selectedKey, SpotlightItem.game(b).key)

        var fresh = SpotlightState()
        fresh.reconcile(with: items, preferredGameID: UUID())
        XCTAssertEqual(fresh.selectedKey, SpotlightItem.game(a).key)

        var cardsOnly = SpotlightState()
        cardsOnly.reconcile(with: [.card(.addGame)])
        XCTAssertEqual(cardsOnly.selectedKey, SpotlightItem.card(.addGame).key)
    }

    func testReconcileKeepsASelectionStillInTheRow() {
        var state = SpotlightState(selectedKey: SpotlightItem.card(.surprise).key, focus: .pills)
        state.reconcile(with: items, preferredGameID: c)
        XCTAssertEqual(state.selectedKey, SpotlightItem.card(.surprise).key)
        XCTAssertEqual(state.focus, .pills)
    }

    func testMoveClampsAndJumps() {
        var state = SpotlightState()
        state.reconcile(with: items)
        XCTAssertTrue(state.move(by: -1, in: items))
        XCTAssertEqual(state.selectedKey, SpotlightItem.card(.addGame).key)
        XCTAssertTrue(state.jump(toEnd: false, in: items))
        XCTAssertFalse(state.move(by: -1, in: items))
        XCTAssertTrue(state.jump(toEnd: true, in: items))
        XCTAssertEqual(state.selectedKey, SpotlightItem.game(c).key)
        XCTAssertFalse(state.move(by: 1, in: items))
    }

    func testScrollOffsetKeepsTheThirdSlot() {
        XCTAssertEqual(SpotlightState.scrollOffset(selectedIndex: 0), 0)
        XCTAssertEqual(SpotlightState.scrollOffset(selectedIndex: 2), 0)
        XCTAssertEqual(SpotlightState.scrollOffset(selectedIndex: 5), 3)
    }

    func testFocusAreasMoveDownAndUp() {
        var state = SpotlightState()
        XCTAssertFalse(state.moveDown(selectedIsGame: false, screenshotCount: 3))
        XCTAssertTrue(state.moveDown(selectedIsGame: true, screenshotCount: 3))
        XCTAssertEqual(state.focus, .pills)
        XCTAssertTrue(state.moveSideways(by: 5, screenshotCount: 3))
        XCTAssertEqual(state.pillIndex, 2)
        XCTAssertTrue(state.moveDown(selectedIsGame: true, screenshotCount: 3))
        XCTAssertEqual(state.focus, .strip)
        XCTAssertTrue(state.moveSideways(by: 4, screenshotCount: 3))
        XCTAssertEqual(state.stripIndex, 2)
        XCTAssertFalse(state.moveSideways(by: 1, screenshotCount: 3))
        XCTAssertTrue(state.moveUp())
        XCTAssertEqual(state.focus, .pills)
        XCTAssertTrue(state.moveUp())
        XCTAssertEqual(state.focus, .row)
        XCTAssertFalse(state.moveUp())
    }

    func testNoStripWithoutScreenshots() {
        var state = SpotlightState(focus: .pills)
        XCTAssertFalse(state.moveDown(selectedIsGame: true, screenshotCount: 0))
        XCTAssertEqual(state.focus, .pills)
    }

    func testFilterShiftClampsAndStartingTabFallsBack() {
        XCTAssertEqual(LibraryFilter.all.shifted(by: -1), .all)
        XCTAssertEqual(LibraryFilter.all.shifted(by: 1), .installed)
        XCTAssertEqual(LibraryFilter.notPlayed.shifted(by: 1), .notPlayed)
        XCTAssertEqual(LibraryFilter(startingTab: "Favorites"), .favorites)
        XCTAssertEqual(LibraryFilter(startingTab: "nonsense"), .all)
    }
}
