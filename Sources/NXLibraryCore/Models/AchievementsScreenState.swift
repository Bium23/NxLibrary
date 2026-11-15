import Foundation

/// Selection on the Achievements screen: a filter and a tile in a two-column list, clamped to its edges.
public struct AchievementsScreenState: Equatable {
    public enum MoveDirection: Sendable { case up, down, left, right }

    public static let columns = 2

    public private(set) var filter: AchievementFilter = .all
    public var index = 0
    /// Tiles in the current filter.
    public private(set) var count: Int

    public init(count: Int) {
        self.count = max(0, count)
    }

    /// Moves within the list; returns whether the selection moved.
    @discardableResult
    public mutating func move(_ direction: MoveDirection) -> Bool {
        guard count > 0 else { return false }
        let column = index % Self.columns
        let next: Int
        switch direction {
        case .left: next = column > 0 ? index - 1 : index
        case .right: next = column < Self.columns - 1 && index + 1 < count ? index + 1 : index
        case .up: next = index >= Self.columns ? index - Self.columns : index
        case .down: next = index + Self.columns < count ? index + Self.columns : index
        }
        defer { index = next }
        return next != index
    }

    /// A new filter starts at its first tile.
    public mutating func setFilter(_ filter: AchievementFilter, count: Int) {
        self.filter = filter
        self.count = max(0, count)
        index = 0
    }

    /// LB/RB: the filter beside the current one, wrapping around.
    public mutating func shiftFilter(by delta: Int, count: Int) {
        let all = AchievementFilter.allCases
        let current = all.firstIndex(of: filter) ?? 0
        let next = ((current + delta) % all.count + all.count) % all.count
        setFilter(all[next], count: count)
    }
}
