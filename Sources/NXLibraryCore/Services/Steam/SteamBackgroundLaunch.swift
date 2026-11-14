import Foundation

/// Waiting for a Steam game that Play started: the launch screen, and keeping Steam out of sight
/// ("Keep Steam in the background"). Valve documents `-silent` (no window at startup, only when Steam
/// is not running yet) and `-nofriendsui`; nothing stops an open Steam from coming forward when it gets
/// `steam://run`, so NX Library hides it for a short while instead. Past the wait's `patience` without
/// the game, Steam may be asking for something (sign-in, an update, a cloud conflict): the launch screen
/// gives way and Steam is shown again.
public enum SteamBackgroundLaunch {
    /// The wait with Steam already open.
    public static let attentionDelay: TimeInterval = 15
    /// The wait when Play has to start Steam, which takes a while before it even looks at the request.
    public static let coldStartDelay: TimeInterval = 45

    public static func patience(steamWasRunning: Bool) -> TimeInterval {
        steamWasRunning ? attentionDelay : coldStartDelay
    }

    /// Arguments for a Steam that Play itself starts; an open Steam ignores launch arguments.
    public static func arguments(enabled: Bool, steamRunning: Bool) -> [String] {
        enabled && !steamRunning ? ["-silent", "-nofriendsui"] : []
    }

    /// Steam is hidden only while this game is on its way and not yet late.
    public static func keepsSteamAway(enabled: Bool, phase: SteamPlayState.Phase, now: Date,
                                      patience: TimeInterval = attentionDelay) -> Bool {
        guard enabled, case .starting(let since, _) = phase else { return false }
        return now.timeIntervalSince(since) <= patience
    }

    /// The game is late: Steam is back in view and the head says to check it.
    public static func mayNeedPlayer(enabled: Bool, phase: SteamPlayState.Phase, now: Date,
                                     patience: TimeInterval = attentionDelay) -> Bool {
        guard enabled, case .starting(let since, _) = phase else { return false }
        return now.timeIntervalSince(since) > patience
    }

    /// Where the launch screen of a Steam game stands.
    public enum LaunchScreen: Equatable, Sendable {
        /// The game is on its way: NX Library stays in front.
        case waiting
        /// The game's app is running: the screen leaves once its window is up.
        case gameStarted
        /// No game within the patience: the screen gives way to Steam.
        case late
        /// Play was cancelled or failed.
        case over
    }

    public static func launchScreen(phase: SteamPlayState.Phase, now: Date, patience: TimeInterval) -> LaunchScreen {
        switch phase {
        case .starting(let since, _): return now.timeIntervalSince(since) > patience ? .late : .waiting
        case .running: return .gameStarted
        case .idle, .failed: return .over
        }
    }
}
