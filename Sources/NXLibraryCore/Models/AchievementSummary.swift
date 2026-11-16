import Foundation

/// The Achievements screen's filters (LB/RB).
public enum AchievementFilter: CaseIterable, Sendable {
    case all, unlocked, locked
}

/// The order of the screen's list (Y), inside the filter. Default: unlocked newest first, then locked most
/// common first. By rarity, the achievements whose rarity is unknown come last; ties keep the default order.
public enum AchievementOrder: CaseIterable, Sendable {
    case `default`, rarest, commonest
}

/// One achievement as the card and the screen show it. A hidden achievement still locked is masked.
public struct AchievementRow: Equatable, Identifiable, Sendable {
    /// Steam's API name.
    public let id: String
    public let name: String
    public let description: String
    /// The color icon once unlocked, the gray one while locked.
    public let icon: String?
    public let unlockedAt: Date?
    /// Share of Steam's players who have it, 0–100; nil while unknown.
    public let percent: Double?
    public let isMasked: Bool

    /// Its crystal from its rarity; nil while the rarity is unknown.
    public var tier: AchievementTier? { AchievementTier.forPercent(percent) }
}

/// A game's achievements for the page's card and the Achievements screen, from `SteamAchievementReader` and
/// Steam's public rarity. Pure: the views only render it.
public struct AchievementSummary: Equatable, Sendable {
    public let total: Int
    public let unlocked: Int
    private let unlockedRows: [AchievementRow]
    private let lockedRows: [AchievementRow]

    public init(achievements: [SteamAchievement], percents: [String: Double]) {
        let rows = achievements.enumerated().map { index, achievement in
            (index, Self.row(achievement, percent: percents[achievement.apiName]))
        }
        total = achievements.count
        unlockedRows = rows.filter { $0.1.unlockedAt != nil }
            .sorted { ($0.1.unlockedAt!, -$0.0) > ($1.1.unlockedAt!, -$1.0) }.map(\.1)
        unlocked = unlockedRows.count
        // Most common first; unknown rarity after, in Steam's order.
        lockedRows = rows.filter { $0.1.unlockedAt == nil }
            .sorted { Self.commoner($0.1.percent, $0.0, than: $1.1.percent, $1.0) }.map(\.1)
    }

    /// Rounded to a whole percent; 0 without achievements.
    public var percentComplete: Int {
        total > 0 ? Int((Double(unlocked) * 100 / Double(total)).rounded()) : 0
    }

    /// The last three unlocked, newest first; before any unlock, the first three locked ones in gray.
    public var recentIcons: [String] {
        Array((unlockedRows.isEmpty ? lockedRows : unlockedRows).compactMap(\.icon).prefix(3))
    }

    /// Unlocked and total per tier. Arcane is one per game, lit when everything is unlocked (0/0 without
    /// achievements); the others count the achievements whose rarity is known.
    public var tierCounts: [AchievementTier: TierCount] {
        var counts: [AchievementTier: TierCount] = [
            .arcane: TierCount(unlocked: total > 0 && unlocked == total ? 1 : 0, total: total > 0 ? 1 : 0),
        ]
        for tier in [AchievementTier.gold, .silver, .bronze] {
            counts[tier] = TierCount(unlocked: unlockedRows.filter { $0.tier == tier }.count,
                                     total: (unlockedRows + lockedRows).filter { $0.tier == tier }.count)
        }
        return counts
    }

    /// The best crystal earned, for the page's card: Arcane with everything unlocked, otherwise the rarest tier
    /// among the unlocked achievements; nil with nothing unlocked or while their rarity is unknown.
    public var bestTier: AchievementTier? {
        if total > 0 && unlocked == total { return .arcane }
        let earned = Set(unlockedRows.compactMap(\.tier))
        return AchievementTier.allCases.first { earned.contains($0) }
    }

    /// Whether Steam's rarity has arrived for any achievement.
    public var hasRarity: Bool { (unlockedRows + lockedRows).contains { $0.percent != nil } }

    /// When the newest unlock happened.
    public var lastUnlockedAt: Date? { unlockedRows.first?.unlockedAt }

    /// The Achievements screen's Recently unlocked strip: the newest unlocked icons first, at most `limit`;
    /// none before the first unlock.
    public func recentUnlockedIcons(limit: Int) -> [String] {
        Array(unlockedRows.compactMap(\.icon).prefix(limit))
    }

    public func rows(_ filter: AchievementFilter, order: AchievementOrder = .default) -> [AchievementRow] {
        let rows: [AchievementRow]
        switch filter {
        case .all: rows = unlockedRows + lockedRows
        case .unlocked: rows = unlockedRows
        case .locked: rows = lockedRows
        }
        guard order != .default else { return rows }
        let rarestFirst = order == .rarest
        // The default position breaks ties, so a re-read never shuffles them.
        let known: [(position: Int, percent: Double, row: AchievementRow)] = rows.enumerated().compactMap { item in
            item.element.percent.map { (item.offset, $0, item.element) }
        }
        let sorted = known.sorted { a, b in
            if a.percent == b.percent { return a.position < b.position }
            return rarestFirst ? a.percent < b.percent : a.percent > b.percent
        }
        return sorted.map(\.row) + rows.filter { $0.percent == nil }
    }

    private static func commoner(_ a: Double?, _ ai: Int, than b: Double?, _ bi: Int) -> Bool {
        switch (a, b) {
        case let (a?, b?): return a != b ? a > b : ai < bi
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return ai < bi
        }
    }

    private static func row(_ achievement: SteamAchievement, percent: Double?) -> AchievementRow {
        let unlocked = achievement.unlockedAt != nil
        let masked = !unlocked && achievement.hidden
        return AchievementRow(
            id: achievement.apiName,
            name: masked ? L10n.text("Hidden achievement") : achievement.name,
            description: masked ? L10n.text("Keep playing to reveal it.") : achievement.description,
            // A masked row never falls back to the color icon: it would give the secret away.
            icon: unlocked ? (achievement.icon ?? achievement.grayIcon)
                : masked ? achievement.grayIcon : (achievement.grayIcon ?? achievement.icon),
            unlockedAt: achievement.unlockedAt,
            percent: percent,
            isMasked: masked)
    }
}
