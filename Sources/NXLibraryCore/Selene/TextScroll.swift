import CoreGraphics

/// A column scrolled inside a window of its own (a mod panel's column: the description, Read more, the files): how
/// far it is scrolled and how far it can go. The offset never leaves the column's ends.
public struct TextScroll: Equatable {
    /// How far the text has moved up, in points.
    public private(set) var offset: CGFloat = 0
    /// The whole text's height, and the window's.
    public private(set) var content: CGFloat = 0
    public private(set) var visible: CGFloat = 0

    /// A controller step moves this much of the window, so its last lines are the next step's first.
    public static let pageFraction: CGFloat = 0.7

    public init() {}

    /// How far the text can move.
    public var reach: CGFloat { max(0, content - visible) }
    public var canScroll: Bool { reach > 0.5 }
    public var atTop: Bool { offset <= 0.5 }
    public var atBottom: Bool { offset >= reach - 0.5 }

    /// The description's height in the column: collapsed, eight lines (or the whole text when it is shorter); after
    /// Read more, the whole text. Opened inside a window of its own, a long description got only the room the
    /// files left, often no more than collapsed.
    public static func windowHeight(text: CGFloat, collapsed: CGFloat, expanded: Bool) -> CGFloat {
        expanded ? text : min(text, collapsed)
    }

    /// A new text or window size; the offset stays inside the text.
    public mutating func setLayout(content: CGFloat, visible: CGFloat) {
        self.content = max(0, content)
        self.visible = max(0, visible)
        offset = clamped(offset)
    }

    /// Moves the text by `delta` (positive shows more below); whether it moved.
    @discardableResult
    public mutating func scroll(by delta: CGFloat) -> Bool {
        let next = clamped(offset + delta)
        guard next != offset else { return false }
        offset = next
        return true
    }

    /// One controller step down or up; whether it moved.
    @discardableResult
    public mutating func page(down: Bool) -> Bool {
        scroll(by: (down ? 1 : -1) * Self.pageFraction * visible)
    }

    public mutating func reset() { offset = 0 }

    /// Moves the window as little as it can to show `span` whole (its top, when it is taller than the window);
    /// whether it moved.
    @discardableResult
    public mutating func reveal(_ span: ClosedRange<CGFloat>) -> Bool {
        var next = offset
        if span.upperBound > offset + visible { next = span.upperBound - visible }
        if span.lowerBound < next { next = span.lowerBound }
        next = clamped(next)
        guard next != offset else { return false }
        offset = next
        return true
    }

    /// What Up or Down did among `rows` (their spans in the column) with the focus on `focus`.
    public enum Step: Equatable {
        /// The focus moved to this row, and the window shows it.
        case focus(Int)
        /// The column moved by a step: there was more to read first.
        case scrolled
        case none
    }

    /// Up or Down: what lies between the window and the next row is read a controller step at a time; once that
    /// row is within a step, the focus moves to it and it shows whole. Past the first or the last row the rest of
    /// the column scrolls.
    public mutating func step(down: Bool, focus: Int, rows: [ClosedRange<CGFloat>]) -> Step {
        let next = focus + (down ? 1 : -1)
        let stride = Self.pageFraction * visible
        guard rows.indices.contains(next) else { return page(down: down) ? .scrolled : .none }
        let row = rows[next]
        let distance = down ? row.upperBound - (offset + visible) : offset - row.lowerBound
        if distance > stride {
            let gap = down ? row.lowerBound - (offset + visible) : offset - row.upperBound
            if scroll(by: (down ? 1 : -1) * min(stride, max(gap, 0))) { return .scrolled }
        }
        reveal(row)
        return .focus(next)
    }

    private func clamped(_ value: CGFloat) -> CGFloat { min(max(value, 0), reach) }
}
