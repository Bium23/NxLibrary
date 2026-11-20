import Foundation

extension SessionSummary {
    public init?(session: PlaySession, game: PortedGame, total: TimeInterval) {
        self.init(session: session, gameID: game.id, gameName: game.name, total: total)
    }
}
