import SwiftUI
import NXLibraryCore

/// A list's own scroll offset (`TextScroll`), the way Selene moves every column: the view shifts its rows by
/// `-state.offset` and draws the lines in view. No scroll view under it, so the wheel and the controller share
/// one offset and one glide, and a step never runs against a scroll still in flight.
@MainActor
final class ListScroll: ObservableObject {
    @Published private(set) var state = TextScroll()

    /// The mod panel's glide: critically damped, so quick notches and held arrows carry on without a bounce.
    static let glide = DetailScroll.glide

    func setLayout(content: CGFloat, visible: CGFloat) {
        var next = state
        next.setLayout(content: content, visible: visible)
        if next != state { state = next }
    }

    /// The wheel (positive shows more below); whether it moved.
    @discardableResult
    func scroll(by delta: CGFloat, animated: Bool) -> Bool {
        var next = state
        guard next.scroll(by: delta) else { return false }
        commit(next, animated: animated)
        return true
    }

    /// Moves as little as it can to show `span` whole; whether it moved.
    @discardableResult
    func reveal(_ span: ClosedRange<CGFloat>, animated: Bool) -> Bool {
        var next = state
        guard next.reveal(span) else { return false }
        commit(next, animated: animated)
        return true
    }

    func reset() {
        guard state.offset != 0 else { return }
        var next = state
        next.reset()
        state = next
    }

    private func commit(_ next: TextScroll, animated: Bool) {
        if animated { withAnimation(Self.glide) { state = next } } else { state = next }
    }
}
