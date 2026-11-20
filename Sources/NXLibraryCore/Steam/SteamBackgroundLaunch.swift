import Foundation

/// The waiting screen and silent launch arguments for Steam games started from Play.
/// A closed Steam can start with `-silent` and `-nofriendsui`. Past the wait's `patience` without the
/// game, the launch screen makes way for Steam so the player can check sign-in, updates or a cloud conflict.
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

    /// The game is late: Steam is back in view and the head says to check it.
    public static func mayNeedPlayer(phase: SteamPlayState.Phase, now: Date,
                                     patience: TimeInterval = attentionDelay) -> Bool {
        guard case .starting(let since) = phase else { return false }
        return now.timeIntervalSince(since) > patience
    }

    /// Where the launch screen of a Steam game stands.
    public enum LaunchScreen: Equatable, Sendable {
        /// The game is on its way: the waiting screen stays up.
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
        case .starting(let since): return now.timeIntervalSince(since) > patience ? .late : .waiting
        case .running: return .gameStarted
        case .idle, .failed: return .over
        }
    }
}
