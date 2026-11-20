import Foundation

/// Whether Arcane comes back to the front when a Steam game quits: the rule of `GameFocus` (the game was the
/// app in front and no other library game is open), and only for a Play pressed in Arcane. A game started
/// from Steam leaves the player in Steam. Each Play counts for one session.
public struct SteamReturnFocus: Equatable, Sendable {
    private var playedHere: Set<UUID> = []
    private var inFront: UUID?

    public init() {}

    public mutating func playPressed(_ gameID: UUID) { playedHere.insert(gameID) }

    /// Play was cancelled or failed before the game ran.
    public mutating func playAbandoned(_ gameID: UUID) { playedHere.remove(gameID) }

    public mutating func gameCameForward(_ gameID: UUID) { inFront = gameID }

    /// Another app stayed in front while this game kept running: the player left the game.
    public mutating func otherAppStayedForward(whileRunning gameID: UUID) {
        if inFront == gameID { inFront = nil }
    }

    public var gameInFront: UUID? { inFront }

    /// The game quit. True when Arcane should come forward.
    /// What a game's quit means: whether Arcane comes back, and whether the player was still in the game.
    public struct Ending: Equatable, Sendable {
        public let returnsToLibrary: Bool
        public let wasInFront: Bool
    }

    public mutating func gameEnded(_ gameID: UUID, othersRunning: Bool) -> Ending {
        let wasInFront = inFront == gameID
        if wasInFront { inFront = nil }
        let playedHere = playedHere.remove(gameID) != nil
        return Ending(returnsToLibrary: playedHere && wasInFront && !othersRunning, wasInFront: wasInFront)
    }
}
