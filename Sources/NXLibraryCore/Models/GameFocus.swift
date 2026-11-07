import Foundation

/// Whether NX Library comes back to the front when a game quits: only when the game was the app in front (the player
/// had not moved to another app while it ran) and no other library game is still open.
public struct GameFocus: Equatable {
    /// The library game in front, by bundle ID.
    public private(set) var gameInFront: String?

    public init() {}

    /// A library game came to the front.
    public mutating func gameCameForward(_ bundleID: String) {
        gameInFront = bundleID
    }

    /// Another app stayed in front while this game kept running: the player left the game.
    public mutating func otherAppStayedForward(whileRunning bundleID: String) {
        if gameInFront == bundleID { gameInFront = nil }
    }

    /// A game quit. True when NX Library should come forward.
    public mutating func gameEnded(_ bundleID: String, othersRunning: Bool) -> Bool {
        guard gameInFront == bundleID else { return false }
        gameInFront = nil
        return !othersRunning
    }
}
