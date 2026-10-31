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

    /// Restarts the failed porting once with the reason's one `--allow-*` flag; the flag is not
    /// remembered, and the Metal gate's flag still comes from the persisted override.
    func portAnyway() {
        guard case .portAnyway(let flag) = portingFailureReason?.action,
              let id = lastBuildGameID,
              let game = libraryGames.first(where: { $0.id == id }) else { return }
        startBuild(for: game, extraArguments: PortingFailureClassifier.arguments([], adding: flag))
    }

    func performFailureAction(_ action: PortingFailureAction, router: AppRouter) {
        switch action {
        case .portAnyway: portAnyway()
        case .openEngineSettings: router.openSettings(.engine)
        case .openSetup: reopenSetup()
        case .importKeys: selectProdKeysFile()
        case .openStorage: router.openSettings(.storage)
        case .none: break
        }
    }
}
