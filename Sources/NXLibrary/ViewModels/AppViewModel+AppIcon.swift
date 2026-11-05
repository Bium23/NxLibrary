import AppKit
import CoreServices
import NXLibraryCore

/// The game app's own icon in Finder and the Dock follows the Icon chosen in Change artwork:
/// - an app without an icon of its own (a Switch 2 NUP, a dump) shows the player's Icon whenever there is one;
/// - an app with the game's icon keeps it, unless the player chose to show their Icon there too (the pop-up after
///   choosing one);
/// - Automatic (no Icon pick) puts the game's own icon back.
/// Written after every build that installs (a rebuild replaces the whole app), and only while the game is not
/// running: otherwise `appIconPending` waits for it to quit (`syncPendingAppIcons`, at launch and on every quit).
extension AppViewModel {
    static let appIconWriter = AppIconWriter()

    private func iconKey(_ game: PortedGame) -> String { game.titleId ?? game.uniqueKey }

    private func installedApp(_ game: PortedGame) -> URL? {
        let app = game.url
        guard app.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path) else { return nil }
        return app
    }

    /// Whether choosing an Icon should ask before changing the app: only when the game has an icon of its own to lose.
    public func shouldAskAboutAppIcon(_ game: PortedGame) -> Bool {
        guard let app = installedApp(game) else { return false }
        return Self.appIconWriter.hasOriginalIcon(app, key: iconKey(game))
    }

    /// The pop-up's answer: show the player's Icon on the app too, or keep the game's own.
    public func setUsesPickedAppIcon(_ use: Bool, for game: PortedGame) {
        updateAppIconState(game) {
            $0.usesPickedAppIcon = use
            $0.appIconPending = true
        }
        syncPendingAppIcons()
    }

    /// The Icon pick changed without a question (an app with no icon of its own, or Automatic).
    public func appIconPickChanged(for game: PortedGame, removed: Bool) {
        updateAppIconState(game) {
            if removed { $0.usesPickedAppIcon = false }
            $0.appIconPending = true
        }
        syncPendingAppIcons()
    }

    /// After a library scan: an app whose icon differs from what the rule wants (a pick chosen while the app was
    /// elsewhere or missing, an app moved or built again, a change lost to a crash) is put right.
    public func reconcileAppIcons() {
        for game in libraryGames where !game.appIconPending && !appIconsInFlight.contains(game.id) {
            guard let app = installedApp(game) else { continue }
            let writer = Self.appIconWriter
            let wantsPick = ArtworkPicks.shared.url(titleID: iconKey(game), slot: .icon) != nil
                && (game.usesPickedAppIcon || !writer.hasOriginalIcon(app, key: iconKey(game)))
            if wantsPick != writer.showsWrittenIcon(app) {
                updateAppIconState(game) { $0.appIconPending = true }
            }
        }
        syncPendingAppIcons()
    }

    /// Writes or puts back every waiting icon whose game is not running and not being built. A change asked for while
    /// the same app is being signed runs again once that finishes, so the last choice wins.
    public func syncPendingAppIcons() {
        for game in libraryGames where game.appIconPending {
            guard !appIconsInFlight.contains(game.id) else {
                appIconRerun.insert(game.id)
                continue
            }
            guard RunningGameMonitor.runningApplication(for: game) == nil,
                  !(isBuilding && currentBuildGameID == game.id) else { continue }
            // No app yet (not built, or moved before the next scan): the change waits for it.
            guard let app = installedApp(game) else { continue }
            let pick = ArtworkPicks.shared.url(titleID: iconKey(game), slot: .icon)
            let writer = Self.appIconWriter
            let key = iconKey(game)
            let usesPick = game.usesPickedAppIcon
            appIconsInFlight.insert(game.id)
            appIconProgress[game.id] = .updating
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var outcome: Result<Bool, Error>
                do {
                    if let pick, usesPick || !writer.hasOriginalIcon(app, key: key) {
                        try writer.apply(image: Data(contentsOf: pick), to: app, key: key)
                        outcome = .success(true)
                    } else if writer.showsWrittenIcon(app) {
                        try writer.restore(app, key: key)
                        outcome = .success(true)
                    } else {
                        outcome = .success(false)
                    }
                } catch {
                    outcome = .failure(error)
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.appIconsInFlight.remove(game.id)
                    let again = self.appIconRerun.remove(game.id) != nil
                    if !again { self.updateAppIconState(game) { $0.appIconPending = false } }
                    switch outcome {
                    case .success(let changed):
                        self.appIconProgress[game.id] = again ? .updating : .updated
                        if changed {
                            Self.refreshIcon(of: app)
                            GameIconProvider.forget(game)
                            GameArtLoader.shared.forget(game)
                            ArtworkPicks.shared.touch()
                            self.logs.append(LogEntry(level: .info, message: "Updated the app icon of \(game.name)."))
                        }
                    case .failure(let error):
                        self.appIconProgress[game.id] = .failed(error.localizedDescription)
                        self.logs.append(LogEntry(level: .error,
                                                  message: "Could not change the app icon of \(game.name): \(error.localizedDescription)"))
                    }
                    if again { self.syncPendingAppIcons() }
                }
            }
        }
    }

    private func updateAppIconState(_ game: PortedGame, _ change: (inout PortedGame) -> Void) {
        guard var library = try? libraryStore.load(),
              let index = library.games.firstIndex(where: { $0.id == game.id }) else { return }
        change(&library.games[index])
        guard (try? libraryStore.save(library)) != nil else { return }
        if let shown = libraryGames.firstIndex(where: { $0.id == game.id }) {
            libraryGames[shown].usesPickedAppIcon = library.games[index].usesPickedAppIcon
            libraryGames[shown].appIconPending = library.games[index].appIconPending
        }
    }

    /// Finder and the Dock read icons through Launch Services, which caches them by the bundle's date.
    private static func refreshIcon(of app: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: app.path)
        LSRegisterURL(app as CFURL, true)
        NSWorkspace.shared.noteFileSystemChanged(app.path)
    }
}

/// Where a game app's icon change stands, shown in Change artwork.
enum AppIconProgress: Equatable {
    case updating, updated
    case failed(String)
}
