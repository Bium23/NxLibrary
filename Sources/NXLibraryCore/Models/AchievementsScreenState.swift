import Foundation

/// Selection on the Achievements screen: a filter and a tile in a two-column list, clamped to its edges.
/// It keeps the rows' ids so a list that changes under it (the rarity arriving, an unlock) keeps the same
/// achievement in focus.
public struct AchievementsScreenState: Equatable {
    public enum MoveDirection: Sendable { case up, down, left, right }

    public static let columns = 2

    public private(set) var filter: AchievementFilter = .all
    public var index = 0
    /// The current filter's rows, by `AchievementRow.id`.
    public private(set) var ids: [String]

    public init(ids: [String]) {
        self.ids = ids
    }

    public var count: Int { ids.count }

    public var focusedID: String? { ids.indices.contains(index) ? ids[index] : nil }

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
    public mutating func setFilter(_ filter: AchievementFilter, ids: [String]) {
        self.filter = filter
        self.ids = ids
        index = 0
    }

    /// LB/RB: the filter beside the current one, wrapping around; `ids` gives each filter's rows.
    public mutating func shiftFilter(by delta: Int, ids: (AchievementFilter) -> [String]) {
        let all = AchievementFilter.allCases
        let current = all.firstIndex(of: filter) ?? 0
        let next = all[((current + delta) % all.count + all.count) % all.count]
        setFilter(next, ids: ids(next))
    }

    /// The list changed under the same filter: the focused achievement keeps the focus where it went;
    /// gone from the list, its place does, inside the list.
    public mutating func setIDs(_ ids: [String]) {
        let focused = focusedID
        self.ids = ids
        index = focused.flatMap { ids.firstIndex(of: $0) } ?? min(index, max(ids.count - 1, 0))
    }
}
