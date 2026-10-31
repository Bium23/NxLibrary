import Foundation

/// The notification at the end of a porting: only when NX Library is not the active app (a porting
/// being watched needs none), never for a cancel, and only while the setting is on.
public enum PortingNotice {
    public static func shouldNotify(success: Bool, cancelled: Bool, enabled: Bool, appActive: Bool) -> Bool {
        enabled && !appActive && !cancelled
    }

    /// `held`: the build finished while the game was open and installs when it quits.
    public static func text(game: String, success: Bool, reason: PortingFailureReason?,
                            held: Bool = false) -> (title: String, body: String) {
        if success { return ("\(game) is ready", held ? "It installs when you quit the game." : "Play it from your library.") }
        return ("\(game) did not port", (reason ?? PortingFailureReason(kind: .unknown)).title)
    }
}
