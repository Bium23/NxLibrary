import Foundation

/// Keeping Steam out of sight while a Steam game starts ("Keep Steam in the background").
/// Valve documents `-silent` (no window at startup, only when Steam is not running yet) and
/// `-nofriendsui`; nothing stops an open Steam from coming forward when it gets `steam://run`,
/// so NX Library hides it for a short while instead. Past `attentionDelay` without the game,
/// Steam may be asking for something (sign-in, an update, a cloud conflict): it is shown again.
public enum SteamBackgroundLaunch {
    public static let attentionDelay: TimeInterval = 15

    /// Arguments for a Steam that Play itself starts; an open Steam ignores launch arguments.
    public static func arguments(enabled: Bool, steamRunning: Bool) -> [String] {
        enabled && !steamRunning ? ["-silent", "-nofriendsui"] : []
    }

    /// Steam is hidden only while this game is on its way and not yet late.
    public static func keepsSteamAway(enabled: Bool, phase: SteamPlayState.Phase, now: Date) -> Bool {
        guard enabled, case .starting(let since, _) = phase else { return false }
        return now.timeIntervalSince(since) <= attentionDelay
    }

    /// The game is late: Steam is back in view and the head says to check it.
    public static func mayNeedPlayer(enabled: Bool, phase: SteamPlayState.Phase, now: Date) -> Bool {
        guard enabled, case .starting(let since, _) = phase else { return false }
        return now.timeIntervalSince(since) > attentionDelay
    }
}
