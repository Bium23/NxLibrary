import AppKit
import NXLibraryCore

/// Builds that finished while their game was running (`PendingInstall`): installed once the game is no longer
/// running, when a game quits, at launch of NX Library and before the game is played again.
extension AppViewModel {
    func installPendingBuilds() {
        guard libraryGames.contains(where: { $0.pendingInstall != nil }) else { return }
        var library = (try? libraryStore.load()) ?? LibraryFile(games: libraryGames)
        var changed = false
        for index in library.games.indices where library.games[index].pendingInstall != nil {
            let name = library.games[index].name
            guard RunningGameMonitor.runningApplication(for: library.games[index]) == nil else { continue }
            do {
                switch try PendingInstaller.install(&library.games[index]) {
                case .installed:
                    logs.append(LogEntry(level: .success, message: "Installed the new build of \(name)."))
                case .gone:
                    logs.append(LogEntry(level: .warning,
                                         message: "The new build of \(name) that waited for the game to quit is gone. Port it again."))
                case nil:
                    continue
                }
                changed = true
                if buildHeldGameID == library.games[index].id { buildHeldGameID = nil }
            } catch {
                logs.append(LogEntry(level: .error,
                                     message: "Could not install the new build of \(name): \(error.localizedDescription)"))
            }
        }
        guard changed else { return }
        try? libraryStore.save(library)
        loadLibrary()
    }

    /// The game as it is after its waiting build went in; the caller has checked it is not running.
    func installingPendingBuild(of game: PortedGame) -> PortedGame {
        guard libraryGames.first(where: { $0.id == game.id })?.pendingInstall != nil else { return game }
        installPendingBuilds()
        return libraryGames.first { $0.id == game.id } ?? game
    }
}
