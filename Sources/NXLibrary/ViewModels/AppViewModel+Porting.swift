import AppKit
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

    func notifyPortingEnded(_ game: PortedGame, success: Bool, held: Bool = false) {
        let appActive = NSApp?.isActive ?? true
        guard PortingNotice.shouldNotify(success: success, cancelled: false,
                                         enabled: settingsStore?.settings.notifyPortingEnds ?? true,
                                         appActive: appActive) else { return }
        NotificationService.shared.sendPortingEnded(gameID: game.id, gameName: game.name, success: success,
                                                    reason: game.portingFailureReason, held: held)
    }

    /// Puts the Porting step back on the last failed porting, from what the game saved.
    func restoreLastFailure() -> Bool {
        guard let id = lastBuildGameID, let game = libraryGames.first(where: { $0.id == id }),
              game.portingFailure == .failed else { return false }
        let reason = game.portingFailureReason ?? PortingFailureReason(kind: .unknown)
        portingFailureReason = reason
        buildError = reason.what(game: game.name)
        buildSuccessPath = nil
        buildState = .failed
        buildWizardStep = 3
        addGameSessionActive = true
        return true
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
