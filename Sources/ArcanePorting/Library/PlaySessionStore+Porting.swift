import Foundation
import NXLibraryCore

extension PlaySessionStore {
    /// A ported game's session: its title ID (or its unique key without one) and the app's bundle ID.
    @discardableResult
    public func start(for game: PortedGame) -> Bool {
        start(gameID: game.id, sourceID: game.titleId ?? game.uniqueKey, bundleID: game.effectiveBundleId)
    }
}
