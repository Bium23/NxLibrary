import Foundation
import NXLibraryCore

extension Surprise {
    /// Hidden games are never picked; "installed" means playable on this Mac. If excluding `excluding` would empty a
    /// pool that held only that game, returns nil.
    public static func pick(from games: [PortedGame],
                            pool: SurprisePool,
                            history: PlayHistory,
                            excluding: UUID?,
                            random: inout some RandomNumberGenerator) -> UUID? {
        pickRecord(from: games, pool: pool, history: history, excluding: excluding, random: &random)
    }
}
