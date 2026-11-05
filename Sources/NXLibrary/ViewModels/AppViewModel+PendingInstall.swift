import AppKit
import NXLibraryCore

/// Builds that finished while their game was running (`PendingInstall`): installed once the game is no longer
/// running, when a game quits, at launch of NX Library and before the game is played again.
extension AppViewModel {
    func installPendingBuilds(only gameID: UUID? = nil) {
        recoverSavesAtStartup()
        guard libraryGames.contains(where: { $0.pendingInstall != nil }) else { return }
        var library = (try? libraryStore.load()) ?? LibraryFile(games: libraryGames)
        var changed = false
        for index in library.games.indices {
            guard gameID == nil || library.games[index].id == gameID else { continue }
            // An explicit retry can still use the in-memory ready build if the
            // previous catalog write failed (for example, a full disk).
            if gameID != nil, library.games[index].pendingInstall == nil {
                library.games[index].pendingInstall = libraryGames.first { $0.id == gameID }?.pendingInstall
            }
            guard library.games[index].pendingInstall != nil else { continue }
            let name = library.games[index].name
            guard RunningGameMonitor.runningApplication(for: library.games[index]) == nil else { continue }
            guard let release = acquireSaveInstallLease(for: library.games[index]) else { continue }
            defer { release() }
            do {
                switch try PendingInstaller.install(&library.games[index]) {
                case .installed:
                    logs.append(LogEntry(level: .success, message: "Installed the new build of \(name)."))
                    library.games[index].appIconPending = true
                    if gameWithInstallFailure?.id == library.games[index].id { gameWithInstallFailure = nil }
                    if canRetryReadyInstall, lastBuildGameID == library.games[index].id {
                        buildState = .succeeded
                        buildSuccessPath = library.games[index].url.path
                        buildError = nil
                        lastError = nil
                        currentStageName = "Build completed"
                        portingProgress?.finish(success: true)
                    }
                case .gone:
                    logs.append(LogEntry(level: .warning,
                                         message: "The new build of \(name) that waited for the game to quit is gone. Port it again."))
                case nil:
                    continue
                }
                changed = true
                if buildHeldGameID == library.games[index].id { buildHeldGameID = nil }
            } catch {
                presentInstallFailure(for: library.games[index], error: error.localizedDescription)
            }
        }
        guard changed else { return }
        try? libraryStore.save(library)
        loadLibrary()
    }

    func presentInstallFailure(for game: PortedGame, error: String) {
        logs.append(LogEntry(level: .error, message: "Could not install the new build of \(game.name): \(error)"))
        installFailureFocus = .cancel
        gameWithInstallFailure = game
    }

    func retryFailedInstallation() {
        guard let game = gameWithInstallFailure else { return }
        gameWithInstallFailure = nil
        installPendingBuilds(only: game.id)
    }

    /// The game as it is after its waiting build went in; the caller has checked it is not running.
    func installingPendingBuild(of game: PortedGame) -> PortedGame {
        guard libraryGames.first(where: { $0.id == game.id })?.pendingInstall != nil else { return game }
        installPendingBuilds()
        return libraryGames.first { $0.id == game.id } ?? game
    }
}
