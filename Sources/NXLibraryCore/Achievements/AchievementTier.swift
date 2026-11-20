import Foundation

/// A tier crystal, as PS5 trophies: one Arcane per game for unlocking everything (the violet crystal, where
/// PS5 has Platinum), and Gold, Silver or Bronze for each achievement from how many Steam players have it.
/// Declared rarest first: the Achievements screen's board shows them in this order.
public enum AchievementTier: CaseIterable, Sendable {
    case arcane, gold, silver, bronze

    /// Fewer than one player in ten.
    public static let goldBelow = 10.0
    /// Fewer than three in ten; the rest is bronze.
    public static let silverBelow = 30.0

    /// An achievement's tier from Steam's global rarity (0–100); nil while unknown. Never arcane.
    public static func forPercent(_ percent: Double?) -> AchievementTier? {
        guard let raw = percent else { return nil }
        // The screen shows one decimal: 9.96 reads "10.0%", so it must not be Gold.
        let percent = (raw * 10).rounded() / 10
        if percent < goldBelow { return .gold }
        if percent < silverBelow { return .silver }
        return .bronze
    }

    /// The tier's crystal: a 1024 px PNG of the maintainer's own art, large enough for the achievement detail, in
    /// Core's resources; found as the translations are (the installed app's bundle first); nil only if it is missing.
    public var imageURL: URL? {
        L10n.resources()?.url(forResource: "crystal-\(self)", withExtension: "png")
    }

    /// Arcane's looping video, the maintainer's own (chosen on 16 Nov 2026): 384 px HEVC with alpha, 180 frames at
    /// 24 fps; nil for the other tiers, which stay still.
    public var videoURL: URL? {
        self == .arcane ? L10n.resources()?.url(forResource: "crystal-arcane", withExtension: "mov") : nil
    }

    /// The tier's name in the app's language (or `context`'s): Arcane, Gold, Silver, Bronze.
    public func displayName(context: AppLocale? = nil) -> String {
        switch self {
        case .arcane: return L10n.text("Arcane", context: context)
        case .gold: return L10n.text("Gold", context: context)
        case .silver: return L10n.text("Silver", context: context)
        case .bronze: return L10n.text("Bronze", context: context)
        }
    }
}

/// How many achievements of a tier are unlocked, out of how many.
public struct TierCount: Equatable, Sendable {
    public let unlocked: Int
    public let total: Int

    public init(unlocked: Int, total: Int) {
        self.unlocked = unlocked
        self.total = total
    }
}
