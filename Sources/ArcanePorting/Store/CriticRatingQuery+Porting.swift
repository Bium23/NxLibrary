import Foundation
import NXLibraryCore

extension CriticRatingQuery {
    /// Use the same console identity as the game's Details, including Switch 2 titles.
    public init(game: PortedGame, name: String? = nil) {
        self.init(name: name ?? game.name, platform: game.isSwitch2 ? .switch2 : .switch)
    }
}
