import Foundation

public enum SpotlightCard: String, Codable, CaseIterable {
    case collection, surprise, activity, mods, addGame

    public var title: String {
        switch self {
        case .collection: return "Collection"
        case .surprise: return "Surprise me"
        case .activity: return "Activity"
        case .mods: return "Mods"
        case .addGame: return "Add Game"
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
    /// `front` (the game being ported) becomes the first game: right after the Add
    /// game card wherever it is, or in the first game's place without it.
    public static func build(games: [PortedGame],
                             enabledCards: [SpotlightCard],
                             order: [String],
                             front: UUID? = nil) -> [SpotlightItem] {
        let enabled = Set(enabledCards)
        let defaults: [SpotlightItem] =
            SpotlightCard.allCases.filter(enabled.contains).map { .card($0) }
            + games.map { .game($0.id) }

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
        if let front, let index = result.firstIndex(of: .game(front)) {
            let item = result.remove(at: index)
            let slot = result.firstIndex(of: .card(.addGame)).map { $0 + 1 }
                ?? result.firstIndex { if case .game = $0 { return true } else { return false } }
                ?? result.endIndex
            result.insert(item, at: slot)
        }
        return result
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
