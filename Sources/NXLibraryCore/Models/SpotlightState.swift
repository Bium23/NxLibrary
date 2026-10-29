import Foundation

/// Where controller focus sits on Spotlight.
public enum SpotlightFocusArea: Equatable {
    case row, pills, strip
    /// The Activity card's top-game tiles.
    case topGames
}

/// A tile lifted off the row to be moved. `order` is the working order (item
/// keys) shown while lifted; `before` is what B restores.
public struct SpotlightLift: Equatable {
    public var key: String
    public var order: [String]
    public var before: [String]
}

/// Selection and focus on the Spotlight screen. Pure state: the view feeds it
/// the row (`SpotlightRow.build`) and the number of screenshots.
public struct SpotlightState: Equatable {
    /// Selene keeps the selection in the third slot once the row scrolls.
    public static let anchorSlot = 2
    /// Play, Details, Favorite.
    public static let pillCount = 3

    public var selectedKey: String?
    public var focus: SpotlightFocusArea
    public var pillIndex: Int
    public var stripIndex: Int
    public var topGameIndex: Int
    /// Non-nil while a tile is lifted for moving.
    public var lift: SpotlightLift?
    /// The starting tab is applied once per app session, on the first visit.
    public var startingTabApplied: Bool

    public init(selectedKey: String? = nil,
                focus: SpotlightFocusArea = .row,
                pillIndex: Int = 0,
                stripIndex: Int = 0,
                topGameIndex: Int = 0,
                startingTabApplied: Bool = false) {
        self.selectedKey = selectedKey
        self.focus = focus
        self.pillIndex = pillIndex
        self.stripIndex = stripIndex
        self.topGameIndex = topGameIndex
        self.startingTabApplied = startingTabApplied
    }

    /// The selected game's id; nil when a card (or nothing) is selected.
    public var selectedGameID: UUID? {
        guard let selectedKey, selectedKey.hasPrefix("game:") else { return nil }
        return UUID(uuidString: String(selectedKey.dropFirst("game:".count)))
    }

    public func selectedIndex(in items: [SpotlightItem]) -> Int? {
        guard let selectedKey else { return nil }
        return items.firstIndex { $0.key == selectedKey }
    }

    public func selectedItem(in items: [SpotlightItem]) -> SpotlightItem? {
        selectedIndex(in: items).map { items[$0] }
    }

    /// Items scrolled off to the left: the selection walks to the anchor slot,
    /// then stays there and the row moves.
    public static func scrollOffset(selectedIndex: Int) -> Int {
        max(0, selectedIndex - anchorSlot)
    }

    /// Keeps a selection that is still in the row; otherwise selects
    /// `preferredGameID`, then the first game, then the first item.
    public mutating func reconcile(with items: [SpotlightItem], preferredGameID: UUID? = nil) {
        if selectedIndex(in: items) != nil { return }
        let preferred = preferredGameID.map { SpotlightItem.game($0) }
        let pick = preferred.flatMap { p in items.first { $0 == p } }
            ?? items.first { if case .game = $0 { return true } else { return false } }
            ?? items.first
        selectedKey = pick?.key
        focus = .row
        pillIndex = 0
        stripIndex = 0
        topGameIndex = 0
    }

    /// Moves the row selection, clamped to the ends. Returns whether it moved.
    @discardableResult
    public mutating func move(by delta: Int, in items: [SpotlightItem]) -> Bool {
        guard !items.isEmpty else { return false }
        // A missing or stale selection counts as the first item, and any move selects.
        let found = selectedIndex(in: items)
        let current = found ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        guard next != current || found == nil else { return false }
        select(items[next])
        return true
    }

    @discardableResult
    public mutating func jump(toEnd: Bool, in items: [SpotlightItem]) -> Bool {
        guard let target = toEnd ? items.last : items.first else { return false }
        let moved = target.key != selectedKey
        select(target)
        return moved
    }

    public mutating func select(_ item: SpotlightItem) {
        selectedKey = item.key
        focus = .row
        pillIndex = 0
        stripIndex = 0
        topGameIndex = 0
    }

    /// Down: row → pills (games only), pills → strip (when it has screenshots).
    @discardableResult
    public mutating func moveDown(selectedIsGame: Bool, screenshotCount: Int,
                                  selectedIsActivity: Bool = false, topGameCount: Int = 0) -> Bool {
        switch focus {
        case .row:
            if selectedIsActivity {
                guard topGameCount > 0 else { return false }
                focus = .topGames
                topGameIndex = 0
                return true
            }
            guard selectedIsGame else { return false }
            focus = .pills
            pillIndex = 0
            return true
        case .pills:
            guard screenshotCount > 0 else { return false }
            focus = .strip
            stripIndex = 0
            return true
        case .strip, .topGames:
            return false
        }
    }

    /// Up: strip → pills → row.
    @discardableResult
    public mutating func moveUp() -> Bool {
        switch focus {
        case .row: return false
        case .pills, .topGames: focus = .row; return true
        case .strip: focus = .pills; return true
        }
    }

    /// Left/Right inside the pills or the strip.
    @discardableResult
    public mutating func moveSideways(by delta: Int, screenshotCount: Int, topGameCount: Int = 0) -> Bool {
        switch focus {
        case .row:
            return false
        case .pills:
            let next = min(max(pillIndex + delta, 0), Self.pillCount - 1)
            defer { pillIndex = next }
            return next != pillIndex
        case .strip:
            guard screenshotCount > 0 else { return false }
            let next = min(max(stripIndex + delta, 0), screenshotCount - 1)
            defer { stripIndex = next }
            return next != stripIndex
        case .topGames:
            guard topGameCount > 0 else { return false }
            let next = min(max(topGameIndex + delta, 0), topGameCount - 1)
            defer { topGameIndex = next }
            return next != topGameIndex
        }
    }

    // MARK: - Moving a tile

    public var isLifted: Bool { lift != nil }

    /// Lifts the selected item. `items` is the row as shown.
    @discardableResult
    public mutating func beginLift(in items: [SpotlightItem]) -> Bool {
        guard lift == nil, let item = selectedItem(in: items) else { return false }
        focus = .row
        let keys = items.map(\.key)
        lift = SpotlightLift(key: item.key, order: keys, before: keys)
        return true
    }

    /// Moves the lifted item by `delta`. `items` is the row as shown (already
    /// in the working order). Returns whether it moved.
    @discardableResult
    public mutating func moveLifted(by delta: Int, in items: [SpotlightItem]) -> Bool {
        guard var lift, let item = items.first(where: { $0.key == lift.key }) else { return false }
        let moved = SpotlightRow.moving(item, by: delta, in: items)
        let keys = moved.map(\.key)
        guard keys != items.map(\.key) else { return false }
        lift.order = keys
        self.lift = lift
        return true
    }

    /// Drops the lifted item; returns the order to save.
    public mutating func drop() -> [String]? {
        guard let lift else { return nil }
        self.lift = nil
        return lift.order
    }

    /// Puts the item back where it was; returns the order that was before.
    @discardableResult
    public mutating func cancelLift() -> [String]? {
        guard let lift else { return nil }
        self.lift = nil
        return lift.before
    }
}

public extension LibraryFilter {
    /// The filter `delta` tabs away, clamped to the ends (LB / RB).
    func shifted(by delta: Int) -> LibraryFilter {
        let all = LibraryFilter.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[min(max(index + delta, 0), all.count - 1)]
    }

    /// `AppSettings.startingTab` raw value, falling back to All games.
    init(startingTab raw: String) {
        self = LibraryFilter(rawValue: raw) ?? .all
    }
}
