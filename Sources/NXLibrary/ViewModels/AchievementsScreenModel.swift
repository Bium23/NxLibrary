import SwiftUI
import NXLibraryCore

/// The open Achievements screen: its selection and its list's scroll. A reference Spotlight keeps while the
/// screen is open, so a step or a scroll redraws the screen (or just its list), never the page beneath.
@MainActor
final class AchievementsScreenModel: ObservableObject {
    @Published private(set) var state: AchievementsScreenState
    let scroll = ListScroll()

    /// The list's geometry in points and the room kept clear above and below the focused row, from the view.
    private var layout: GridListLayout?
    private var above: CGFloat = 0
    private var below: CGFloat = 0
    private var animates = true
    /// The wheel moved the list since the last arrow or click: only then can the focus be out of view.
    private var wheeled = false

    init(ids: [String]) {
        state = AchievementsScreenState(ids: ids)
    }

    enum Outcome { case ignored, moved, filtered, close }

    /// The arrows move through the list, LB/RB switch the filter, B closes; the host swallows the rest.
    func handle(_ action: GamepadAction, summary: AchievementSummary) -> Outcome {
        switch action {
        case .navigateLeft: return move(.left) ? .moved : .ignored
        case .navigateRight: return move(.right) ? .moved : .ignored
        case .navigateUp: return move(.up) ? .moved : .ignored
        case .navigateDown: return move(.down) ? .moved : .ignored
        case .tabPrevious, .tabNext:
            shiftFilter(by: action == .tabPrevious ? -1 : 1, summary: summary)
            return .filtered
        case .cancel: return .close
        default: return .ignored
        }
    }

    /// The list's size, from the view whenever it or the canvas changes.
    func setLayout(_ layout: GridListLayout, visible: CGFloat, above: CGFloat, below: CGFloat, animates: Bool) {
        self.layout = layout
        self.above = above
        self.below = below
        self.animates = animates
        scroll.setLayout(content: layout.contentHeight(count: state.count), visible: visible)
    }

    /// After the wheel the focused row may be out of view: the first arrow brings the focus to the nearest
    /// row in view instead of moving on from one the player can't see.
    @discardableResult
    func move(_ direction: AchievementsScreenState.MoveDirection) -> Bool {
        var next = state
        let afterWheel = wheeled
        wheeled = false
        if afterWheel, let layout, let nearest = layout.nearestVisible(index: next.index, count: next.count,
                                                           offset: scroll.state.offset, visible: scroll.state.visible,
                                                           above: above, below: below) {
            next.index = nearest
        } else if !next.move(direction) {
            return false
        }
        state = next
        reveal()
        return true
    }

    /// The wheel or the trackpad (positive shows more below).
    func wheel(by delta: CGFloat, animated: Bool) {
        if scroll.scroll(by: delta, animated: animated) { wheeled = true }
    }

    /// A click on a row.
    func focus(_ index: Int) {
        wheeled = false
        guard index != state.index, (0..<state.count).contains(index) else { return }
        var next = state
        next.index = index
        state = next
        reveal()
    }

    func setFilter(_ filter: AchievementFilter, summary: AchievementSummary) {
        var next = state
        next.setFilter(filter, ids: summary.rows(filter).map(\.id))
        filterChanged(next)
    }

    func shiftFilter(by delta: Int, summary: AchievementSummary) {
        var next = state
        next.shiftFilter(by: delta) { summary.rows($0).map(\.id) }
        filterChanged(next)
    }

    /// A re-read while the screen is open: the selection stays inside the list, the list where it was.
    func setIDs(_ ids: [String]) {
        var next = state
        next.setIDs(ids)
        guard next != state else { return }
        state = next
        relayout()
    }

    /// A new filter opens at its top, at once: a glide across a different list would show rows that are gone.
    private func filterChanged(_ next: AchievementsScreenState) {
        wheeled = false
        state = next
        scroll.reset()
        relayout()
    }

    private func relayout() {
        guard let layout else { return }
        scroll.setLayout(content: layout.contentHeight(count: state.count), visible: scroll.state.visible)
    }

    private func reveal() {
        guard let layout, state.count > 0 else { return }
        scroll.reveal(layout.revealSpan(of: state.index, above: above, below: below), animated: animates)
    }
}
