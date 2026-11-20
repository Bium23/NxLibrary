import Foundation

/// Paging for the full-screen screenshot viewer. Left/Right stop at the ends
/// (no wraparound), like Selene's captures player.
public struct ScreenshotViewerState: Equatable {
    public let count: Int
    public private(set) var index: Int

    /// `start` is clamped into `0..<count` (0 when there are no screenshots).
    public init(count: Int, start: Int = 0) {
        self.count = max(0, count)
        self.index = Self.clamp(start, count: max(0, count))
    }

    public static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }

    /// "3 / 6", 1-based; empty when there is nothing to show.
    public var label: String { count > 0 ? "\(index + 1) / \(count)" : "" }

    /// Moves by `delta`, stopping at the ends. Returns whether the index changed.
    @discardableResult
    public mutating func move(by delta: Int) -> Bool {
        let next = Self.clamp(index + delta, count: count)
        guard next != index else { return false }
        index = next
        return true
    }

    @discardableResult public mutating func next() -> Bool { move(by: 1) }
    @discardableResult public mutating func previous() -> Bool { move(by: -1) }
}
