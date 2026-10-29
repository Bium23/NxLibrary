import Foundation

/// "More like this" for the Details page: other games ranked by shared
/// developer/publisher (+2) and shared genres (+1 each).
public enum MoreLikeThis {
    public static func pick(for game: PortedGame, in games: [PortedGame],
                            metadata: (UUID) -> NintendoStoreMetadata?, limit: Int = 6) -> [UUID] {
        guard limit > 0, let mine = metadata(game.id) else { return [] }
        let makers = Set((mine.developers + mine.publishers).map(normalized).filter { !$0.isEmpty })
        let genres = Set(mine.genres.map(normalized).filter { !$0.isEmpty })
        var scored: [(game: PortedGame, score: Int)] = []
        for other in games where other.id != game.id && !other.isHidden {
            guard let theirs = metadata(other.id) else { continue }
            var score = 0
            let theirMakers = Set((theirs.developers + theirs.publishers).map(normalized))
            if !makers.isDisjoint(with: theirMakers) { score += 2 }
            score += genres.intersection(Set(theirs.genres.map(normalized))).count
            if score > 0 { scored.append((other, score)) }
        }
        scored.sort { a, b in
            a.score != b.score ? a.score > b.score
                : a.game.name.localizedCaseInsensitiveCompare(b.game.name) == .orderedAscending
        }
        return scored.prefix(limit).map { $0.game.id }
    }

    private static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
