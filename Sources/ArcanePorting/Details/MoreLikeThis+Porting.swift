import Foundation
import NXLibraryCore

extension MoreLikeThis {
    /// Ported games ranked by the Nintendo store's makers and genres.
    public static func pick(for game: PortedGame, in games: [PortedGame],
                            metadata: (UUID) -> NintendoStoreMetadata?, limit: Int = 6) -> [UUID] {
        rank(for: game, in: games, name: \.name, hidden: \.isHidden, limit: limit) { record in
            metadata(record.id).map { Traits(developers: $0.developers, publishers: $0.publishers, genres: $0.genres) }
        }
    }
}
