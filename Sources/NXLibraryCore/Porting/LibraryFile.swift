import Foundation

public struct LibraryFile: Codable, Equatable {
    public var schemaVersion: Int
    public var games: [PortedGame]

    public init(schemaVersion: Int = 1, games: [PortedGame] = []) {
        self.schemaVersion = schemaVersion
        self.games = games
    }
}
