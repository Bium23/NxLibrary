import Foundation

/// "More like this" for the Details page: other games ranked by shared
/// developer/publisher (+2) and shared genres (+1 each).
public enum MoreLikeThis {
    public struct Traits: Sendable {
        public let developers: [String]
        public let publishers: [String]
        public let genres: [String]

        public init(developers: [String] = [], publishers: [String] = [], genres: [String] = []) {
            self.developers = developers
            self.publishers = publishers
            self.genres = genres
        }

        public init(steam metadata: SteamMetadata) {
            self.init(developers: metadata.developers, publishers: metadata.publishers, genres: metadata.genres)
        }
    }

    /// Prefer the current source. A caller can opt into matching across the library when that source has no match.
    public static func pick(for game: CatalogGame, in games: [CatalogGame],
                            fallbackToOtherSources: Bool = false, traits: (CatalogGame) -> Traits?, limit: Int = 6) -> [UUID] {
        let sameSource = rank(for: game, in: games, name: \.name,
                              hidden: { $0.isHidden || $0.integration != game.integration }, limit: limit, traits: traits)
        guard sameSource.isEmpty, fallbackToOtherSources else { return sameSource }
        return rank(for: game, in: games, name: \.name,
                    hidden: { $0.isHidden || $0.integration == game.integration }, limit: limit, traits: traits)
    }

    package static func rank<Game: Identifiable>(for game: Game, in games: [Game],
                                          name: (Game) -> String, hidden: (Game) -> Bool,
                                          limit: Int, traits: (Game) -> Traits?) -> [UUID] where Game.ID == UUID {
        guard limit > 0, let mine = traits(game) else { return [] }
        let makers = Set((mine.developers + mine.publishers).map(normalized).filter { !$0.isEmpty })
        let genres = Set(mine.genres.map(normalized).filter { !$0.isEmpty && $0 != "other" })
        var scored: [(game: Game, score: Int)] = []
        for other in games where other.id != game.id && !hidden(other) {
            guard let theirs = traits(other) else { continue }
            var score = 0
            let theirMakers = Set((theirs.developers + theirs.publishers).map(normalized))
            if !makers.isDisjoint(with: theirMakers) { score += 2 }
            score += genres.intersection(Set(theirs.genres.map(normalized))).count
            if score > 0 { scored.append((other, score)) }
        }
        scored.sort { a, b in
            a.score != b.score ? a.score > b.score
                : name(a.game).localizedCaseInsensitiveCompare(name(b.game)) == .orderedAscending
        }
        return scored.prefix(limit).map { $0.game.id }
    }

    private static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
