import CoreGraphics

/// A list of equal rows in columns, scrolled by an offset of its own (`TextScroll`) rather than a scroll view:
/// where each row sits, how tall the whole list is, which lines to draw for a window, and where the focus goes
/// when the wheel left it out of view. Points throughout; line 0 is the top one.
public struct GridListLayout: Equatable, Sendable {
    public let columns: Int
    public let rowHeight: CGFloat
    public let spacing: CGFloat
    /// Room above the first line (for its focus ring) and below the last (so it can rise clear of the hints).
    public let topPad: CGFloat
    public let bottomRoom: CGFloat

    public init(columns: Int, rowHeight: CGFloat, spacing: CGFloat, topPad: CGFloat, bottomRoom: CGFloat) {
        self.columns = max(columns, 1)
        self.rowHeight = rowHeight
        self.spacing = spacing
        self.topPad = topPad
        self.bottomRoom = bottomRoom
    }

    private var pitch: CGFloat { rowHeight + spacing }

    public func lines(count: Int) -> Int { (max(count, 0) + columns - 1) / columns }

    public func contentHeight(count: Int) -> CGFloat {
        let lines = lines(count: count)
        return topPad + CGFloat(lines) * rowHeight + CGFloat(max(lines - 1, 0)) * spacing + bottomRoom
    }

    public func top(of index: Int) -> CGFloat { top(line: index / columns) }

    private func top(line: Int) -> CGFloat { topPad + CGFloat(line) * pitch }

    /// The row with `above` and `below` of room around it: what the window shows when the row has the focus.
    public func revealSpan(of index: Int, above: CGFloat, below: CGFloat) -> ClosedRange<CGFloat> {
        let top = top(of: index)
        return (top - above)...(top + rowHeight + below)
    }

    /// The lines that touch the window, widened by `buffer` each side so a glide has its rows drawn already.
    public func visibleLines(count: Int, offset: CGFloat, visible: CGFloat, buffer: CGFloat) -> ClosedRange<Int>? {
        let lines = lines(count: count)
        guard lines > 0 else { return nil }
        let low = offset - buffer, high = offset + visible + buffer
        let first = max(0, Int(((low - topPad - rowHeight) / pitch).rounded(.up)))
        let last = min(lines - 1, Int(((high - topPad) / pitch).rounded(.down)))
        return first <= last ? first...last : nil
    }

    /// After the wheel, the focused row may be out of view: the nearest line shown whole between the margins,
    /// in the same column (the line's last row when it is short). Nil while the focused row is in view (its
    /// middle inside the window, margins or not: a row at the very top stays focused) or when no line fits.
    public func nearestVisible(index: Int, count: Int, offset: CGFloat, visible: CGFloat,
                               above: CGFloat, below: CGFloat) -> Int? {
        let lines = lines(count: count)
        guard count > 0, lines > 0 else { return nil }
        let line = min(max(index, 0), count - 1) / columns
        let middle = top(line: line) + rowHeight / 2
        if middle >= offset, middle <= offset + visible { return nil }
        // A point of slack: an offset left by a reveal against a margin is not exact.
        let bandTop = offset + above - 1, bandBottom = offset + visible - below + 1
        func whole(_ line: Int) -> Bool { top(line: line) >= bandTop && top(line: line) + rowHeight <= bandBottom }
        let shown = (0..<lines).filter(whole)
        guard let nearest = shown.min(by: { abs($0 - line) < abs($1 - line) }) else { return nil }
        return min(nearest * columns + index % columns, count - 1)
    }
}
