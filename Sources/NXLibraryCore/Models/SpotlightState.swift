import Foundation

/// Where controller focus sits on Spotlight. Below the pills the screen is one
/// page that scrolls up: screenshots, About this game beside Build & Sources, More like this.
public enum SpotlightFocusArea: Hashable {
    case row, pills, strip
    /// About this game's Read more, left of Build & Sources.
    case about
    /// Build & Sources' actions, `SpotlightState.actionColumns` to a row.
    case actions
    /// More like this.
    case more
    /// The Mods band, between the screenshots and About this game.
    case mods
    /// The Activity card's top-game tiles.
    case topGames
    /// The Mods card's store, below the card; `ModStoreFocus` moves inside it.
    case store
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
    /// Play, Options, Favorite.
    public static let pillCount = 3
    /// Build & Sources lays its actions out as small buttons, three to a row.
    public static let actionColumns = 3

    public var selectedKey: String?
    public var focus: SpotlightFocusArea
    public var pillIndex: Int
    public var stripIndex: Int
    public var topGameIndex: Int
    public var actionIndex = 0
    /// Pills on screen now: one while a game ports, otherwise `pillCount`.
    public private(set) var pillLimit = SpotlightState.pillCount
    public var moreIndex = 0
    public var modsIndex = 0
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

    @discardableResult
    public mutating func showGameDetails() -> Bool {
        guard selectedGameID != nil, !isLifted else { return false }
        focus = .pills
        pillIndex = 0
        return true
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
            ?? items.first { $0 == .card(.addGame) }
            ?? items.first
        selectedKey = pick?.key
        focus = .row
        pillIndex = 0
        stripIndex = 0
        topGameIndex = 0
        actionIndex = 0
        moreIndex = 0
        modsIndex = 0
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

    /// The pills changed (a porting started or ended): keep the focus on one that exists.
    public mutating func setPillLimit(_ limit: Int) {
        pillLimit = max(1, limit)
        pillIndex = min(pillIndex, pillLimit - 1)
    }

    public mutating func select(_ item: SpotlightItem) {
        selectedKey = item.key
        focus = .row
        pillIndex = 0
        stripIndex = 0
        topGameIndex = 0
        actionIndex = 0
        moreIndex = 0
        modsIndex = 0
    }

    /// Down: row → pills (games only) → strip → Build & Sources (row by row) → Mods (row by row) →
    /// More like this, skipping whatever is empty.
    @discardableResult
    public mutating func moveDown(selectedIsGame: Bool, screenshotCount: Int,
                                  selectedIsActivity: Bool = false, topGameCount: Int = 0,
                                  actionCount: Int = 0, moreCount: Int = 0, modsCount: Int = 0) -> Bool {
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
            if screenshotCount > 0 {
                // The strip keeps the tile it had, so it does not slide back.
                focus = .strip
                stripIndex = min(stripIndex, screenshotCount - 1)
                return true
            }
            return enterActions(actionCount: actionCount, moreCount: moreCount, modsCount: modsCount)
        case .strip:
            return enterActions(actionCount: actionCount, moreCount: moreCount, modsCount: modsCount)
        case .actions:
            if let below = Self.actionBelow(actionIndex, count: actionCount) {
                actionIndex = below
                return true
            }
            return enterMods(modsCount: modsCount, moreCount: moreCount)
        case .about:
            return enterMods(modsCount: modsCount, moreCount: moreCount)
        case .mods:
            if let below = ModsBandLayout.below(modsIndex, count: modsCount) {
                modsIndex = below
                return true
            }
            return enterMore(moreCount: moreCount)
        case .more, .topGames, .store:
            return false
        }
    }

    /// Down into the Mods grid lands on its first row, in the column it had.
    private mutating func enterMods(modsCount: Int, moreCount: Int) -> Bool {
        guard modsCount > 0 else { return enterMore(moreCount: moreCount) }
        focus = .mods
        modsIndex = ModsBandLayout.entryFromAbove(modsIndex, count: modsCount)
        return true
    }

    private mutating func enterMore(moreCount: Int) -> Bool {
        guard moreCount > 0 else { return false }
        focus = .more
        moreIndex = 0
        return true
    }

    /// The action under `index` in the next row; above a short last row's gap, its last action.
    public static func actionBelow(_ index: Int, count: Int) -> Int? {
        if index + actionColumns < count { return index + actionColumns }
        let lastRowStart = max(count - 1, 0) / actionColumns * actionColumns
        return index < lastRowStart ? count - 1 : nil
    }

    private mutating func enterActions(actionCount: Int, moreCount: Int, modsCount: Int) -> Bool {
        guard actionCount > 0 else { return enterMods(modsCount: modsCount, moreCount: moreCount) }
        focus = .actions
        actionIndex = 0
        return true
    }

    /// Up: More like this → Mods (row by row) → Build & Sources (row by row) → strip → pills → row.
    @discardableResult
    public mutating func moveUp(screenshotCount: Int = 1, actionCount: Int = 0, modsCount: Int = 0) -> Bool {
        let aboveActions: SpotlightFocusArea = screenshotCount > 0 ? .strip : .pills
        switch focus {
        case .row: return false
        case .pills, .topGames, .store: focus = .row
        case .strip: focus = .pills
        case .about:
            focus = aboveActions
        case .actions:
            if actionIndex >= Self.actionColumns {
                actionIndex -= Self.actionColumns
            } else {
                focus = aboveActions
            }
        case .mods:
            if let above = ModsBandLayout.above(modsIndex) {
                modsIndex = above
            } else {
                enterLastActionRow(actionCount: actionCount, otherwise: aboveActions)
            }
        case .more:
            if modsCount > 0 {
                // Up into the Mods grid lands on its last row, in the column it had.
                focus = .mods
                modsIndex = ModsBandLayout.entryFromBelow(modsIndex, count: modsCount)
            } else {
                enterLastActionRow(actionCount: actionCount, otherwise: aboveActions)
            }
        }
        return true
    }

    /// Up into Build & Sources lands on its last row's first action.
    private mutating func enterLastActionRow(actionCount: Int, otherwise: SpotlightFocusArea) {
        guard actionCount > 0 else {
            focus = otherwise
            return
        }
        focus = .actions
        actionIndex = ((actionCount - 1) / Self.actionColumns) * Self.actionColumns
    }

    /// Left/Right inside the pills, the strip, Build & Sources or More like this.
    /// Left of Build & Sources' first column is Read more, when `readMore`.
    @discardableResult
    public mutating func moveSideways(by delta: Int, screenshotCount: Int, topGameCount: Int = 0,
                                      actionCount: Int = 0, moreCount: Int = 0, readMore: Bool = false,
                                      modsCount: Int = 0) -> Bool {
        switch focus {
        case .mods:
            guard let next = ModsBandLayout.beside(modsIndex, by: delta, count: modsCount) else { return false }
            modsIndex = next
            return true
        case .about:
            guard delta > 0, actionCount > 0 else { return false }
            focus = .actions
            actionIndex -= actionIndex % Self.actionColumns
            return true
        case .actions:
            let column = actionIndex % Self.actionColumns
            if delta < 0, column == 0 {
                guard readMore else { return false }
                focus = .about
                return true
            }
            let next = actionIndex + (delta < 0 ? -1 : 1)
            guard delta < 0 ? column > 0 : (column < Self.actionColumns - 1 && next < actionCount) else { return false }
            actionIndex = next
            return true
        case .more:
            guard moreCount > 0 else { return false }
            let next = min(max(moreIndex + delta, 0), moreCount - 1)
            defer { moreIndex = next }
            return next != moreIndex
        case .row, .store:
            return false
        case .pills:
            let next = min(max(pillIndex + delta, 0), pillLimit - 1)
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

public extension LibraryFilter {
    /// The next filter, wrapping from the last back to the first (RS on Collection).
    func cycled() -> LibraryFilter {
        let all = LibraryFilter.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}
