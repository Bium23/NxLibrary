import Foundation

/// Where controller focus sits on Spotlight.
public enum SpotlightFocusArea: Equatable {
    case row, pills, strip
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
    /// The starting tab is applied once per app session, on the first visit.
    public var startingTabApplied: Bool

    public init(selectedKey: String? = nil,
                focus: SpotlightFocusArea = .row,
                pillIndex: Int = 0,
                stripIndex: Int = 0,
                startingTabApplied: Bool = false) {
        self.selectedKey = selectedKey
        self.focus = focus
        self.pillIndex = pillIndex
        self.stripIndex = stripIndex
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
    }

    /// Down: row → pills (games only), pills → strip (when it has screenshots).
    @discardableResult
    public mutating func moveDown(selectedIsGame: Bool, screenshotCount: Int) -> Bool {
        switch focus {
        case .row:
            guard selectedIsGame else { return false }
            focus = .pills
            pillIndex = 0
            return true
        case .pills:
            guard screenshotCount > 0 else { return false }
            focus = .strip
            stripIndex = 0
            return true
        case .strip:
            return false
        }
    }

    /// Up: strip → pills → row.
    @discardableResult
    public mutating func moveUp() -> Bool {
        switch focus {
        case .row: return false
        case .pills: focus = .row; return true
        case .strip: focus = .pills; return true
        }
    }

    /// Left/Right inside the pills or the strip.
    @discardableResult
    public mutating func moveSideways(by delta: Int, screenshotCount: Int) -> Bool {
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
        }
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
