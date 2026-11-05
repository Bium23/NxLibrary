import Foundation

/// The sources Change artwork browses on their own, from their "Browse online" tiles, the way the Theme screen
/// browses wallpaper sites: a search prefilled with the game's name, its results for the open tab, each credited, and
/// the source's page a key press away.
public enum ArtworkBrowseSource: String, CaseIterable, Sendable {
    case launchBox, steamGridDB

    public var title: String {
        switch self {
        case .launchBox: return "LaunchBox"
        case .steamGridDB: return "SteamGridDB"
        }
    }

    public var site: URL {
        switch self {
        case .launchBox: return LaunchBoxArt.site
        case .steamGridDB: return SteamGridDBArt.site
        }
    }

    /// SteamGridDB answers only with the player's own key.
    public var needsKey: Bool { self == .steamGridDB }

    /// What one search found: the game's page on the source, or nil when it has no such game, and its images for
    /// every slot.
    public struct Found: Equatable, Sendable {
        public let page: URL?
        public let candidates: [ArtworkCandidate]

        public init(page: URL?, candidates: [ArtworkCandidate]) {
            self.page = page
            self.candidates = candidates
        }
    }

    /// The names a search tries: the game's own names while the field still holds its name, else what was typed.
    public static func names(for query: String, gameNames: [String]) -> [String] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        if let first = gameNames.first, first.caseInsensitiveCompare(term) == .orderedSame { return gameNames }
        return [term]
    }

    /// Searches the source. A name the player searches is taken loosely: the first Switch result (LaunchBox) or the
    /// first result (SteamGridDB) when no title matches it exactly.
    public func search(_ query: String, gameNames: [String], switch2: Bool, key: String?,
                       client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> Found {
        let names = Self.names(for: query, gameNames: gameNames)
        guard !names.isEmpty else { return Found(page: nil, candidates: []) }
        switch self {
        case .launchBox:
            let game = await LaunchBoxArt.game(names: names, switch2: switch2, loose: true, client: client)
            return Found(page: game?.page, candidates: game?.candidates ?? [])
        case .steamGridDB:
            guard let key else { return Found(page: nil, candidates: []) }
            let game = await SteamGridDBArt.game(names: names, key: key, loose: true, client: client)
            return Found(page: game?.page, candidates: game?.candidates ?? [])
        }
    }
}
