import Foundation

public enum MoveDirection {
    case left, right, up, down
}

/// The Setup check's card grid (Selene's SetupScreen): rows as even as possible,
/// each centred, so a short last row sits in the middle.
public enum SetupGrid {
    public static func rowCounts(_ count: Int, maxPerRow: Int = 6) -> [Int] {
        guard count > 0 else { return [] }
        let rows = (count + maxPerRow - 1) / maxPerRow
        return (0..<rows).map { count / rows + ($0 < count % rows ? 1 : 0) }
    }

    public static func row(of index: Int, rowCounts: [Int]) -> Int {
        var start = 0
        for (row, n) in rowCounts.enumerated() {
            if index < start + n { return row }
            start += n
        }
        return rowCounts.count - 1
    }

    private static func start(of row: Int, rowCounts: [Int]) -> Int {
        rowCounts.prefix(row).reduce(0, +)
    }

    /// The card's x from the centre, in cells.
    public static func offset(of index: Int, rowCounts: [Int]) -> Double {
        let r = row(of: index, rowCounts: rowCounts)
        return Double(index - start(of: r, rowCounts: rowCounts)) - Double(rowCounts[r] - 1) / 2
    }

    /// nil when there is no card that way (Down from the last row goes to the buttons).
    public static func move(from index: Int, _ direction: MoveDirection, rowCounts: [Int]) -> Int? {
        let r = row(of: index, rowCounts: rowCounts)
        let first = start(of: r, rowCounts: rowCounts)
        switch direction {
        case .left: return index > first ? index - 1 : nil
        case .right: return index < first + rowCounts[r] - 1 ? index + 1 : nil
        case .up, .down:
            let target = r + (direction == .down ? 1 : -1)
            guard rowCounts.indices.contains(target) else { return nil }
            return nearest(in: target, to: offset(of: index, rowCounts: rowCounts),
                           tieRight: direction == .down, rowCounts: rowCounts)
        }
    }

    /// A card exactly between two: Down picks the right one, Up the left one, so Up then Down comes back.
    private static func nearest(in row: Int, to x: Double, tieRight: Bool, rowCounts: [Int]) -> Int {
        let first = start(of: row, rowCounts: rowCounts)
        var best = first
        for i in first..<(first + rowCounts[row]) {
            let d = abs(offset(of: i, rowCounts: rowCounts) - x)
            let b = abs(offset(of: best, rowCounts: rowCounts) - x)
            if tieRight ? d <= b + 0.001 : d < b - 0.001 { best = i }
        }
        return best
    }
}
