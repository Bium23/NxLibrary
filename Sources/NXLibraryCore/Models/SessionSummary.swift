import Foundation

/// What the session card says when a game closes: the game, this session and the game's total, the total written as
/// the game info writes it. Sessions shorter than `minimumDuration` (a launch closed again) show no card.
public struct SessionSummary: Equatable, Identifiable {
    public static let minimumDuration: TimeInterval = 10

    /// The session's own ID, so the same session never shows twice.
    public let id: UUID
    public let gameID: UUID
    public let gameName: String
    public let thisSession: String
    public let total: String

    public init?(session: PlaySession, game: PortedGame, total: TimeInterval) {
        guard session.gameID == game.id, let length = session.duration,
              length >= Self.minimumDuration else { return nil }
        id = session.id
        gameID = game.id
        gameName = game.name
        thisSession = Self.duration(length)
        self.total = Self.duration(max(total, length))
    }

    static func duration(_ interval: TimeInterval) -> String {
        interval < 60 ? "<1m" : LibraryPresentation.duration(interval)
    }
}
