import Foundation

/// A tier crystal, as PS5 trophies: one Arcane per game for unlocking everything, and Radiant, Aether or Ember
/// for each achievement from how many Steam players have it. The cases keep the art's materials; players see
/// `displayName`. Declared rarest first: the Achievements screen's board shows them in this order.
public enum AchievementTier: CaseIterable, Sendable {
    case platinum, gold, silver, bronze

    /// Fewer than one player in ten.
    public static let goldBelow = 10.0
    /// Fewer than three in ten; the rest is bronze.
    public static let silverBelow = 30.0

    /// An achievement's tier from Steam's global rarity (0–100); nil while unknown. Never platinum.
    public static func forPercent(_ percent: Double?) -> AchievementTier? {
        guard let percent else { return nil }
        if percent < goldBelow { return .gold }
        if percent < silverBelow { return .silver }
        return .bronze
    }

    /// The tier's crystal: a prerendered 256 px PNG (`.superpowers/arcane`, recipe v2, tight crop) in Core's
    /// resources, found as the translations are (the installed app's bundle first); nil only if it is missing.
    public var imageURL: URL? {
        L10n.resources()?.url(forResource: "crystal-\(self)", withExtension: "png")
    }

    /// The tier's name: a proper name, the same in every language.
    public var displayName: String {
        switch self {
        case .platinum: return L10n.text("Arcane")
        case .gold: return L10n.text("Radiant")
        case .silver: return L10n.text("Aether")
        case .bronze: return L10n.text("Ember")
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
