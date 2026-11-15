import Foundation

/// The Achievements screen's filters.
public enum AchievementFilter: CaseIterable, Sendable {
    case all, unlocked, locked, rarest
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

    /// Fewer than one player in ten has it.
    public var isRare: Bool { percent.map { $0 < Self.rareBelow } ?? false }
    public static let rareBelow = 10.0
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

    /// The unlocked achievement the fewest players have, when its rarity is known.
    public var rarestUnlocked: AchievementRow? {
        unlockedRows.filter { $0.percent != nil }.min { $0.percent! < $1.percent! }
    }

    public func rows(_ filter: AchievementFilter) -> [AchievementRow] {
        switch filter {
        case .all: return unlockedRows + lockedRows
        case .unlocked: return unlockedRows
        case .locked: return lockedRows
        case .rarest:
            let all = unlockedRows + lockedRows
            let known = all.filter { $0.percent != nil }.sorted { $0.percent! < $1.percent! }
            return known + all.filter { $0.percent == nil }
        }
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
