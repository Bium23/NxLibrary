import Foundation
import NXLibraryCore

/// What the home shows of the porting: the tile look, the pills and the time line.
extension AppViewModel {
    /// The game being ported now, if any.
    var portingGameID: UUID? { isBuilding ? currentBuildGameID : nil }

    func portingTileLook(_ game: PortedGame) -> PortingTileLook {
        PortingTileLook.make(game: game, portingGameID: portingGameID, progress: portingProgress)
    }

    func portingPills(_ game: PortedGame) -> PortingPills {
        PortingPills.make(game: game, portingGameID: portingGameID)
    }

    /// "About 8 min left" under the Porting pill; nil before the shaders.
    var portingETAText: String? {
        guard isBuilding, let portingProgress else { return nil }
        return PortingETA.text(portingProgress, lastFinishingSeconds: lastPortingFinishSeconds)
    }
}
