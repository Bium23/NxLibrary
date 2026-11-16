import Foundation

public enum SpotlightCard: String, Codable, CaseIterable {
    case collection, surprise, activity, mods, addGame

    public var title: String {
        switch self {
        case .collection: return L10n.text("Collection")
        case .surprise: return L10n.text("Surprise me")
        case .activity: return L10n.text("Activity")
        case .mods: return L10n.text("Mods")
        case .addGame: return L10n.text("Add Game")
        }
    }

    public var icon: MaterialIcon {
        switch self {
        case .collection: return .collections
        case .surprise: return .casino
        case .activity: return .timeline
        case .mods: return .puzzle
        case .addGame: return .add
        }
    }
}

public enum SpotlightItem: Hashable {
    case card(SpotlightCard)
    case game(UUID)

    public var key: String {
        switch self {
        case .card(let c): return "card:\(c.rawValue)"
        case .game(let id): return "game:\(id.uuidString)"
        }
    }
}

public enum SpotlightRow {
    /// Builds the Spotlight row.
    ///
    /// Default sequence: enabled cards (in `SpotlightCard.allCases` order), then
    /// `games` in the order given. The saved `order` (item keys) is then applied:
    /// items whose key is in `order` take the relative positions `order` gives
    /// them (keys that no longer exist are ignored). Items not in `order` keep
    /// their default relative position: each is placed immediately after the
    /// ordered item that preceded it in the default sequence, or at the start
    /// when no ordered item preceded it.
    ///
    /// `front` (the game being ported, then the games Steam downloads: `leaders`) become
    /// the first games, in that order: right after the Add game card wherever it is, or
    /// in the first game's place without it.
    public static func build(gameIDs: [UUID], enabledCards: [SpotlightCard], order: [String], front: [UUID] = []) -> [SpotlightItem] {
        let enabled = Set(enabledCards)
        let defaults: [SpotlightItem] =
            SpotlightCard.allCases.filter(enabled.contains).map { .card($0) }
            + gameIDs.map { .game($0) }

        var rank: [String: Int] = [:]
        for (i, key) in order.enumerated() where rank[key] == nil { rank[key] = i }

        var ordered: [SpotlightItem] = []
        var leading: [SpotlightItem] = []
        var trailing: [String: [SpotlightItem]] = [:]
        var lastOrderedKey: String?
        for item in defaults {
            if rank[item.key] != nil {
                ordered.append(item)
                lastOrderedKey = item.key
            } else if let anchor = lastOrderedKey {
                trailing[anchor, default: []].append(item)
            } else {
                leading.append(item)
            }
        }
        ordered.sort { rank[$0.key]! < rank[$1.key]! }

        var result = leading
        for item in ordered {
            result.append(item)
            result.append(contentsOf: trailing[item.key] ?? [])
        }
        let leaders = front.map { SpotlightItem.game($0) }.filter(result.contains)
        guard !leaders.isEmpty else { return result }
        result.removeAll(where: leaders.contains)
        let slot = result.firstIndex(of: .card(.addGame)).map { $0 + 1 }
            ?? result.firstIndex { if case .game = $0 { return true } else { return false } }
            ?? result.endIndex
        result.insert(contentsOf: leaders, at: slot)
        return result
    }

    /// The games that lead the row, as Nintendo's home leads with a game it is preparing: the
    /// one being ported, then those Steam downloads (or has finished downloading) this session,
    /// in the row's order. Only games in `row` lead.
    public static func leaders(porting: UUID?, downloads: Set<UUID>, row: [UUID]) -> [UUID] {
        let shown = Set(row)
        let first = porting.flatMap { shown.contains($0) ? [$0] : nil } ?? []
        return first + row.filter { downloads.contains($0) && $0 != porting }
    }

    /// Folds a reordered *visible* subsequence (a filtered row) back into the
    /// full saved order. `fullOrder` is the unfiltered row's keys; the slots the
    /// visible keys occupy are refilled, in sequence, with `visibleOrder`, so
    /// everything not visible keeps its slot. Keys of `visibleOrder` that are
    /// not in `fullOrder` are ignored.
    public static func merging(visibleOrder: [String], into fullOrder: [String]) -> [String] {
        let present = Set(fullOrder)
        let visible = visibleOrder.filter(present.contains)
        let visibleSet = Set(visible)
        var queue = visible[...]
        return fullOrder.map { key in
            guard visibleSet.contains(key), let next = queue.popFirst() else { return key }
            return next
        }
    }

    /// Save a visible move without losing hidden/disabled games or cards.
    /// `gameIDs` must include the whole catalog, not only its visible projection.
    public static func saving(visibleOrder: [String], gameIDs: [UUID], previousOrder: [String]) -> [String] {
        let full = build(gameIDs: gameIDs, enabledCards: SpotlightCard.allCases, order: previousOrder).map(\.key)
        return merging(visibleOrder: visibleOrder, into: full)
    }

    /// A game started: it becomes the first game of a saved order, which otherwise stays as it was
    /// (cards keep their places). Without a saved order nothing is saved: the row already leads with
    /// the most recently played game.
    public static func playing(_ gameID: UUID, previousOrder: [String]) -> [String] {
        guard !previousOrder.isEmpty else { return [] }
        let key = SpotlightItem.game(gameID).key
        var order = previousOrder.filter { $0 != key }
        let firstGame = order.firstIndex { $0.hasPrefix("game:") } ?? order.endIndex
        order.insert(key, at: firstGame)
        return order
    }

    /// Moves `item` by `delta` positions, clamped to the row's ends.
    /// Returns `items` unchanged if the item is absent.
    public static func moving(_ item: SpotlightItem, by delta: Int,
                              in items: [SpotlightItem]) -> [SpotlightItem] {
        guard let index = items.firstIndex(of: item) else { return items }
        let target = min(max(index + delta, 0), items.count - 1)
        guard target != index else { return items }
        var copy = items
        copy.remove(at: index)
        copy.insert(item, at: target)
        return copy
    }
}

public enum SurprisePool: String, Codable, CaseIterable {
    case installed, notPlayed, all
}

public enum Surprise {
    /// Hidden games are never picked. If excluding `excluding` would empty a
    /// pool that held only that game, returns nil.
    public static func pick(from games: [PortedGame],
                            pool: SurprisePool,
                            history: PlayHistory,
                            excluding: UUID?,
                            random: inout some RandomNumberGenerator) -> UUID? {
        let visible = games.filter { !$0.isHidden }
        let pooled: [PortedGame]
        switch pool {
        case .installed: pooled = visible.filter(\.isPlayableLocally)
        case .notPlayed: pooled = visible.filter { history.lastPlayed(for: $0.id) == nil }
        case .all: pooled = visible
        }
        let candidates = pooled.filter { $0.id != excluding }
        return candidates.randomElement(using: &random)?.id
    }
}

/// The Steam games seen downloading since NX Library started. They lead Spotlight's row
/// (`SpotlightRow.leaders`) until quit, also once Steam has finished them, as a ported
/// game does: the player finds the new game first, ready to play.
public struct SessionDownloads: Equatable {
    public private(set) var ids: Set<UUID> = []

    public init() {}

    /// Remembers the games downloading now. True when one is new.
    @discardableResult
    public mutating func note(_ games: [CatalogGame]) -> Bool {
        let downloading = games.filter { $0.steamGame?.isDownloading == true }.map(\.id)
        let before = ids.count
        ids.formUnion(downloading)
        return ids.count != before
    }
}
