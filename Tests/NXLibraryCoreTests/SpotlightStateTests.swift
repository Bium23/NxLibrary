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

    func testReconcileResetsFocusAndIndicesWhenTheSelectionVanishes() {
        var state = SpotlightState(selectedKey: SpotlightItem.game(UUID()).key,
                                   focus: .strip, pillIndex: 2, stripIndex: 4)
        state.reconcile(with: items, preferredGameID: b)
        XCTAssertEqual(state.selectedKey, SpotlightItem.game(b).key)
        XCTAssertEqual(state.focus, .row)
        XCTAssertEqual(state.pillIndex, 0)
        XCTAssertEqual(state.stripIndex, 0)

        var emptied = SpotlightState(selectedKey: SpotlightItem.game(a).key, focus: .pills, pillIndex: 1)
        emptied.reconcile(with: [])
        XCTAssertNil(emptied.selectedKey)
        XCTAssertEqual(emptied.focus, .row)
        XCTAssertEqual(emptied.pillIndex, 0)
    }

    func testSelectResetsFocusAndIndices() {
        var state = SpotlightState(selectedKey: SpotlightItem.game(a).key,
                                   focus: .strip, pillIndex: 2, stripIndex: 3)
        state.select(.game(c))
        XCTAssertEqual(state.selectedKey, SpotlightItem.game(c).key)
        XCTAssertEqual(state.focus, .row)
        XCTAssertEqual(state.pillIndex, 0)
        XCTAssertEqual(state.stripIndex, 0)
    }

    func testJumpReturnsFalseWhenAlreadyAtThatEnd() {
        var state = SpotlightState(selectedKey: SpotlightItem.game(c).key)
        XCTAssertFalse(state.jump(toEnd: true, in: items))
        XCTAssertEqual(state.selectedKey, SpotlightItem.game(c).key)
        var start = SpotlightState(selectedKey: SpotlightItem.card(.surprise).key)
        XCTAssertFalse(start.jump(toEnd: false, in: items))
        XCTAssertFalse(start.jump(toEnd: true, in: []))
    }

    func testMoveWithAStaleSelectionSelectsFromTheStart() {
        var left = SpotlightState(selectedKey: SpotlightItem.game(UUID()).key, focus: .pills)
        XCTAssertTrue(left.move(by: -1, in: items))
        XCTAssertEqual(left.selectedKey, SpotlightItem.card(.surprise).key)
        XCTAssertEqual(left.focus, .row)

        var right = SpotlightState(selectedKey: SpotlightItem.game(UUID()).key)
        XCTAssertTrue(right.move(by: 1, in: items))
        XCTAssertEqual(right.selectedKey, SpotlightItem.card(.addGame).key)

        var empty = SpotlightState(selectedKey: "game:stale")
        XCTAssertFalse(empty.move(by: 1, in: []))
    }

    func testSelectedGameIDOnlyForGames() {
        XCTAssertEqual(SpotlightState(selectedKey: SpotlightItem.game(a).key).selectedGameID, a)
        XCTAssertNil(SpotlightState(selectedKey: SpotlightItem.card(.collection).key).selectedGameID)
        XCTAssertNil(SpotlightState().selectedGameID)
    }
}

final class SpotlightLiftTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()
    private var items: [SpotlightItem] { [.card(.surprise), .game(a), .game(b), .game(c)] }

    private func lifted(_ key: SpotlightItem) -> SpotlightState {
        var s = SpotlightState(selectedKey: key.key)
        XCTAssertTrue(s.beginLift(in: items))
        return s
    }

    func testBeginLiftNeedsSelection() {
        var s = SpotlightState(selectedKey: nil)
        XCTAssertFalse(s.beginLift(in: items))
        XCTAssertFalse(s.isLifted)
    }

    func testMoveLiftedSwapsAndClamps() {
        var s = lifted(.game(b))
        XCTAssertTrue(s.moveLifted(by: -1, in: items))
        XCTAssertEqual(s.lift?.order, [items[0].key, items[2].key, items[1].key, items[3].key])
        // The view feeds the working order back in.
        func working() -> [SpotlightItem] { s.lift!.order.compactMap { k in items.first { $0.key == k } } }
        XCTAssertTrue(s.moveLifted(by: -1, in: working()))
        XCTAssertEqual(s.lift?.order.first, items[2].key)
        XCTAssertFalse(s.moveLifted(by: -1, in: working()), "clamped at the start")
    }

    func testDropReturnsWorkingOrder() {
        var s = lifted(.game(a))
        XCTAssertTrue(s.moveLifted(by: 1, in: items))
        let order = s.drop()
        XCTAssertEqual(order, [items[0].key, items[2].key, items[1].key, items[3].key])
        XCTAssertFalse(s.isLifted)
        XCTAssertNil(s.drop())
    }

    func testCancelRestoresBefore() {
        var s = lifted(.game(c))
        XCTAssertTrue(s.moveLifted(by: -2, in: items))
        XCTAssertEqual(s.cancelLift(), items.map(\.key))
        XCTAssertFalse(s.isLifted)
        XCTAssertEqual(s.selectedKey, SpotlightItem.game(c).key)
    }

    func testActivityDownEntersTopGames() {
        var s = SpotlightState(selectedKey: SpotlightItem.card(.activity).key)
        XCTAssertFalse(s.moveDown(selectedIsGame: false, screenshotCount: 0, selectedIsActivity: true, topGameCount: 0))
        XCTAssertTrue(s.moveDown(selectedIsGame: false, screenshotCount: 0, selectedIsActivity: true, topGameCount: 3))
        XCTAssertEqual(s.focus, .topGames)
        XCTAssertTrue(s.moveSideways(by: 5, screenshotCount: 0, topGameCount: 3))
        XCTAssertEqual(s.topGameIndex, 2)
        XCTAssertTrue(s.moveUp())
        XCTAssertEqual(s.focus, .row)
    }

    func testFilterCyclesForwardAndWraps() {
        XCTAssertEqual(LibraryFilter.all.cycled(), .installed)
        XCTAssertEqual(LibraryFilter.favorites.cycled(), .notPlayed)
        XCTAssertEqual(LibraryFilter.notPlayed.cycled(), .all)
    }

    func testCollectionRowScrollsPastAnchor() {
        XCTAssertEqual(CollectionRow.scrollOffset(selectedIndex: 0), 0)
        XCTAssertEqual(CollectionRow.scrollOffset(selectedIndex: CollectionRow.anchorSlot), 0)
        XCTAssertEqual(CollectionRow.scrollOffset(selectedIndex: CollectionRow.anchorSlot + 3), 3)
    }

    func testCollectionCoversAreSwitchCaseShaped() {
        XCTAssertEqual(CollectionRow.coverWidth / CollectionRow.coverHeight, BoxArt.aspectRatio, accuracy: 0.003)
        XCTAssertEqual(BoxArt.aspectRatio, 1166.0 / 1888.0, accuracy: 0.0001)
        // The row still fits its band with the selected cover grown.
        XCTAssertLessThan(CollectionRow.coverHeight * CollectionRow.selectedScale, CollectionRow.bandHeight)
    }

    func testPageScrollsThroughActionsAndMore() {
        // Seven actions in rows of three: 0 1 2 / 3 4 5 / 6.
        XCTAssertEqual(SpotlightState.actionColumns, 3)
        var s = SpotlightState(selectedKey: "game:x", focus: .strip)
        XCTAssertTrue(s.moveDown(selectedIsGame: true, screenshotCount: 3, actionCount: 7, moreCount: 2))
        XCTAssertEqual(s.focus, .actions)
        for _ in 0..<2 { XCTAssertTrue(s.moveSideways(by: 1, screenshotCount: 3, actionCount: 7)) }
        XCTAssertEqual(s.actionIndex, 2)
        XCTAssertFalse(s.moveSideways(by: 1, screenshotCount: 3, actionCount: 7))
        XCTAssertTrue(s.moveDown(selectedIsGame: true, screenshotCount: 3, actionCount: 7, moreCount: 2))
        XCTAssertEqual(s.actionIndex, 5)
        // Above the short last row's gap, Down lands on its last action.
        XCTAssertTrue(s.moveDown(selectedIsGame: true, screenshotCount: 3, actionCount: 7, moreCount: 2))
        XCTAssertEqual(s.actionIndex, 6)
        XCTAssertTrue(s.moveDown(selectedIsGame: true, screenshotCount: 3, actionCount: 7, moreCount: 2))
        XCTAssertEqual(s.focus, .more)
        XCTAssertFalse(s.moveDown(selectedIsGame: true, screenshotCount: 3, actionCount: 7, moreCount: 2))
        XCTAssertTrue(s.moveUp(screenshotCount: 3, actionCount: 7))
        XCTAssertEqual(s.focus, .actions)
        XCTAssertEqual(s.actionIndex, 6)
        XCTAssertTrue(s.moveUp(screenshotCount: 3, actionCount: 7))
        XCTAssertEqual(s.actionIndex, 3)
        XCTAssertTrue(s.moveUp(screenshotCount: 3, actionCount: 7))
        XCTAssertEqual(s.actionIndex, 0)
        XCTAssertTrue(s.moveUp(screenshotCount: 3, actionCount: 7))
        XCTAssertEqual(s.focus, .strip)
    }

    func testPillsSkipEmptyStripToActions() {
        var s = SpotlightState(selectedKey: "game:x", focus: .pills)
        XCTAssertTrue(s.moveDown(selectedIsGame: true, screenshotCount: 0, actionCount: 4))
        XCTAssertEqual(s.focus, .actions)
        XCTAssertTrue(s.moveUp(screenshotCount: 0, actionCount: 4))
        XCTAssertEqual(s.focus, .pills)
    }

    func testReadMoreSitsLeftOfTheActions() {
        var s = SpotlightState(selectedKey: "game:x", focus: .actions)
        s.actionIndex = 4
        XCTAssertTrue(s.moveSideways(by: -1, screenshotCount: 3, actionCount: 7, readMore: true))
        XCTAssertEqual(s.actionIndex, 3)
        XCTAssertTrue(s.moveSideways(by: -1, screenshotCount: 3, actionCount: 7, readMore: true))
        XCTAssertEqual(s.focus, .about)
        XCTAssertFalse(s.moveSideways(by: -1, screenshotCount: 3, actionCount: 7, readMore: true))
        XCTAssertTrue(s.moveSideways(by: 1, screenshotCount: 3, actionCount: 7, readMore: true))
        XCTAssertEqual(s.focus, .actions)
        XCTAssertEqual(s.actionIndex, 3)
        // Without Read more the grid's left edge stops.
        s.actionIndex = 0
        XCTAssertFalse(s.moveSideways(by: -1, screenshotCount: 3, actionCount: 7))
        XCTAssertEqual(s.focus, .actions)
    }

    func testReadMoreGoesUpToTheStripAndDownToMore() {
        var s = SpotlightState(selectedKey: "game:x", focus: .about)
        XCTAssertTrue(s.moveDown(selectedIsGame: true, screenshotCount: 3, actionCount: 7, moreCount: 2))
        XCTAssertEqual(s.focus, .more)
        s.focus = .about
        XCTAssertFalse(s.moveDown(selectedIsGame: true, screenshotCount: 3, actionCount: 7, moreCount: 0))
        XCTAssertTrue(s.moveUp(screenshotCount: 3, actionCount: 7))
        XCTAssertEqual(s.focus, .strip)
    }

    func testStripKeepsItsTileAcrossTheBands() {
        var s = SpotlightState(selectedKey: "game:x", focus: .strip, stripIndex: 4)
        XCTAssertTrue(s.moveDown(selectedIsGame: true, screenshotCount: 6, actionCount: 7))
        XCTAssertTrue(s.moveUp(screenshotCount: 6, actionCount: 7))
        XCTAssertEqual(s.focus, .strip)
        XCTAssertEqual(s.stripIndex, 4)
        XCTAssertTrue(s.moveUp(screenshotCount: 6, actionCount: 7))
        XCTAssertTrue(s.moveDown(selectedIsGame: true, screenshotCount: 6, actionCount: 7))
        XCTAssertEqual(s.focus, .strip)
        XCTAssertEqual(s.stripIndex, 4)
    }
}
