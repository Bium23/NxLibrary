import AppKit
import Foundation
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

/// What a failed porting offers: Port anyway, the notification and the failure's actions.
extension PortingModel {
    // MARK: - Failure actions
    /// Restarts the failed porting once with the reason's one `--allow-*` flag; the flag is not
    /// remembered, and the Metal gate's flag still comes from the persisted override.
    func portAnyway() {
        guard case .portAnyway(let flag) = self.portingFailureReason?.action,
              let id = app.lastBuildGameID,
              let game = app.libraryGames.first(where: { $0.id == id }) else { return }
        startBuild(for: game, extraArguments: PortingFailureClassifier.arguments([], adding: flag))
    }

    func notifyPortingEnded(_ game: PortedGame, success: Bool, held: Bool = false) {
        let appActive = NSApp?.isActive ?? true
        guard PortingNotice.shouldNotify(success: success, cancelled: false,
                                         enabled: app.settingsStore?.settings.notifyPortingEnds ?? true,
                                         appActive: appActive) else { return }
        NotificationService.shared.sendPortingEnded(gameID: game.id, gameName: game.name, success: success,
                                                    reason: game.portingFailureReason, held: held)
    }

    /// Puts the Porting step back on the last failed porting, from what the game saved.
    func restoreLastFailure() -> Bool {
        guard let id = app.lastBuildGameID, let game = app.libraryGames.first(where: { $0.id == id }),
              game.portingFailure == .failed else { return false }
        let reason = game.portingFailureReason ?? PortingFailureReason(kind: .unknown)
        self.portingFailureReason = reason
        self.buildError = reason.what(game: game.name)
        self.buildSuccessPath = nil
        self.buildState = .failed
        self.buildWizardStep = 3
        self.addGameSessionActive = true
        return true
    }

    func performFailureAction(_ action: PortingFailureAction, router: AppRouter) {
        switch action {
        case .portAnyway: portAnyway()
        case .openEngineSettings: router.openSettings(.engine)
        case .openSetup: app.reopenSetup()
        case .importKeys: app.setup.selectProdKeysFile()
        case .openStorage: router.openSettings(.portingStorage)
        case .none: break
        }
    }
}
