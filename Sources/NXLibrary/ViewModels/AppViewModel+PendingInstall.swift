import AppKit
import NXLibraryCore

/// Builds that finished while their game was running (`PendingInstall`): installed once the game is no longer
/// running, when a game quits, at launch of NX Library and before the game is played again.
extension AppViewModel {
    @discardableResult
    func authorizeDevelopmentOperation(_ kind: DevelopmentOperationStore.Kind, game: PortedGame) -> Bool {
        do { try developmentOperations.authorize(kind, gameID: game.id); return true }
        catch {
            logs.append(LogEntry(level: .error, message: error.localizedDescription))
            showSettingsNotice(title: L10n.text("Options not saved"), message: L10n.text("Your changes could not be saved. Try again."))
            return false
        }
    }

    func installPendingBuilds(only gameID: UUID? = nil, automatic: Bool = true) {
        recoverSavesAtStartup()
        let candidates = Set(libraryGames.filter { $0.pendingInstall != nil }.map(\.id))
            .union(catalogBuildRecoveries.values.filter { $0.pendingInstall != nil }.map(\.id))
        for id in candidates {
            guard gameID == nil || id == gameID else { continue }
            if automatic && (!developmentOperations.permits(.build, gameID: id) || catalogBuildRecoveries[id] != nil) { continue }
            let recoveryGeneration = catalogBuildRecoveries[id]
            var outcome: PortedGame?
            var release: (() -> Void)?
            defer { release?() }
            do {
                let catalog = try catalogRepository.updateNXNative(id: id) { game in
                    guard let candidate = try catalogBuildRecoveries.pendingCandidate(persisted: game, explicitRetry: !automatic) else { return }
                    game = candidate
                    guard game.pendingInstall != nil else {
                        if recoveryGeneration != nil { outcome = game }
                        return
                    }
                    if !automatic {
                        guard authorizeDevelopmentOperation(.build, game: game),
                              authorizeDevelopmentOperation(.icon, game: game) else { return }
                    }
                    guard RunningGameMonitor.runningApplication(for: game) == nil else { return }
                    guard let lease = acquireSaveInstallLease(for: game) else { return }
                    release = lease
                    switch try PendingInstaller.install(&game) {
                    case .installed:
                        _ = authorizeDevelopmentOperation(.icon, game: game)
                        game.appIconPending = true
                        logs.append(LogEntry(level: .success, message: L10n.format("Installed the new build of %@.", [game.name])))
                        if let path = game.lastBuild?.logPath, !path.isEmpty { appIconBuildLogs[id] = URL(fileURLWithPath: path) }
                    case .gone:
                        logs.append(LogEntry(level: .warning, message: L10n.format("The new build of %@ that waited for the game to quit is gone. Port it again.", [game.name])))
                    case nil: return
                    }
                    outcome = game
                }
                applyCatalog(catalog)
                guard let outcome else { continue }
                catalogBuildRecoveries.acknowledge(id: id, matching: recoveryGeneration)
                if gameWithInstallFailure?.id == id { gameWithInstallFailure = nil }
                if buildHeldGameID == id { buildHeldGameID = nil }
                if lastBuildGameID == id, outcome.pendingInstall == nil, outcome.status == .built {
                    buildState = .succeeded; buildSuccessPath = outcome.url.path
                    buildError = nil; lastError = nil; currentStageName = "Build completed"
                    portingProgress?.finish(success: true)
                }
            } catch {
                if let outcome { _ = persistBuildOutcome(outcome) }
                else if let game = libraryGames.first(where: { $0.id == id }) {
                    presentInstallFailure(for: game, error: error.localizedDescription)
                } else { reportCatalogFailure(error) }
            }
        }
    }

    func presentInstallFailure(for game: PortedGame, error: String) {
        logs.append(LogEntry(level: .error, message: L10n.format("Could not install the new build of %@: %@", [String(describing: (game.name)), String(describing: (error))])))
        installFailureFocus = .cancel
        gameWithInstallFailure = game
    }

    func retryFailedInstallation() {
        guard let game = gameWithInstallFailure else { return }
        gameWithInstallFailure = nil
        installPendingBuilds(only: game.id, automatic: false)
    }

    /// The game as it is after its waiting build went in; the caller has checked it is not running.
    func installingPendingBuild(of game: PortedGame) -> PortedGame {
        guard libraryGames.first(where: { $0.id == game.id })?.pendingInstall != nil else { return game }
        installPendingBuilds()
        return libraryGames.first { $0.id == game.id } ?? game
    }
}
