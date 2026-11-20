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

    /// A catalog game's session: a Steam game's card reads like an nxnative one's.
    public init?(session: PlaySession, game: CatalogGame, total: TimeInterval) {
        self.init(session: session, gameID: game.id, gameName: game.name, total: total)
    }

    package init?(session: PlaySession, gameID: UUID, gameName: String, total: TimeInterval) {
        guard session.gameID == gameID, let length = session.duration,
              length >= Self.minimumDuration else { return nil }
        id = session.id
        self.gameID = gameID
        self.gameName = gameName
        thisSession = Self.duration(length)
        self.total = Self.duration(max(total, length))
    }

    package static func duration(_ interval: TimeInterval) -> String {
        interval < 60 ? "<1m" : LibraryPresentation.duration(interval)
    }
}
