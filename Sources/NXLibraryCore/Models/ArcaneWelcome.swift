import Foundation

/// The one-time "Welcome to Arcane" screen for players who update from NX Library: when it shows,
/// the Steam offer it may carry, its focus and how every exit marks it shown.
public enum ArcaneWelcome {
    /// Once, after the update: setup already done, never shown, and no save recovery or failed
    /// install waiting (those screens come first, so the welcome waits for them).
    public static func shouldShow(setupCompleted: Bool, shown: Bool, hasPendingRecovery: Bool) -> Bool {
        setupCompleted && !shown && !hasPendingRecovery
    }

    public enum Offer: Equatable, Sendable {
        case steam(gameCount: Int)
    }

    /// Steam is offered only when it was found with games and its source is still off.
    public static func offer(steamEnabled: Bool, steamGameCount: Int?) -> Offer? {
        guard !steamEnabled, let count = steamGameCount, count > 0 else { return nil }
        return .steam(gameCount: count)
    }

    /// Open library, or B / Esc.
    public enum Exit: CaseIterable, Sendable { case openLibrary, back }

    public static func markShown(_ settings: AppSettings) -> AppSettings {
        var next = settings
        next.welcomeArcaneShown = true
        return next
    }

    /// Every exit marks the welcome shown, so it never comes back.
    public static func settings(after exit: Exit, from settings: AppSettings) -> AppSettings {
        markShown(settings)
    }

    public enum Focus: Equatable, Sendable {
        case add, notNow, openLibrary

        public static func order(offer: Offer?) -> [Focus] {
            offer == nil ? [.openLibrary] : [.add, .notNow, .openLibrary]
        }

        public static func initial(offer: Offer?) -> Focus { order(offer: offer)[0] }

        /// Add and Not now sit side by side on the offer row; Open library is below it.
        public func moved(_ direction: MoveDirection, offer: Offer?) -> Focus {
            guard offer != nil else { return .openLibrary }
            switch (self, direction) {
            case (.add, .right): return .notNow
            case (.notNow, .left): return .add
            case (.add, .down), (.notNow, .down): return .openLibrary
            case (.openLibrary, .up): return .add
            default: return self
            }
        }
    }
}
