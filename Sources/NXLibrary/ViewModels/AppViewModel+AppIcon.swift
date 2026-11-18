import AppKit
import CoreServices
import NXLibraryCore

/// The Icon chosen in Change artwork can stay only inside NX Library or also appear in Finder and the Dock.
/// The explicit choice applies to every game, including apps with no original icon. Legacy libraries keep their
/// previous automatic behavior until the player makes a choice. Automatic changes the source, preserving scope.
/// Written after every build that installs (a rebuild replaces the whole app), and only while the game is not
/// running: otherwise `appIconPending` waits for it to quit (`syncPendingAppIcons`, at launch and on every quit).
extension AppViewModel {
    static let appIconWriter = AppIconWriter()
    static let automaticIconArtwork = ArtworkStore()

    private func iconKey(_ game: PortedGame) -> String { personalizationKey(for: game) }

    /// Resolve the image independently of whether the player wants it applied to the Mac app.
    func automaticIconURL(for game: PortedGame) async -> URL? {
        if let original = Self.appIconWriter.originalIconURL(game.url, key: iconKey(game)) { return original }
        if let workspace = game.workspacePath, let titleID = game.titleId {
            let extracted = URL(fileURLWithPath: workspace).appendingPathComponent("\(titleID)_build/extract/v0/icon.jpg")
            if NSImage(contentsOf: extracted) != nil { return extracted }
        }
        guard let titleID = game.titleId else { return nil }
        return await Self.automaticIconArtwork.automaticIcon(titleID: titleID, name: game.name)
    }

    func usesIconOnMac(for game: PortedGame) -> Bool {
        let current = libraryGames.first { $0.id == game.id } ?? game
        return current.appIconOnMac ?? (current.usesPickedAppIcon || !Self.appIconWriter.hasOriginalIcon(current.url, key: iconKey(current)))
    }

    private func installedApp(_ game: PortedGame) -> URL? {
        let app = game.url
        guard app.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path) else { return nil }
        return app
    }

    /// Keep one cancellable Play request while the app is being signed; signing itself must finish safely.
    func waitForAppIconBeforeLaunching(_ game: PortedGame) {
        showSettingsNotice(title: L10n.format("Preparing %@", [String(describing: (game.name))]),
                           message: L10n.text("Preparing the app icon. The game will start when it is ready. This can take a minute for a large game."),
                           cancelTitle: L10n.text("Cancel"))
        guard let notice = settingsNotice else { return }
        iconLaunchWait.begin(gameID: game.id, noticeID: notice.id)
        launchingGameId = game.id
        SoundEffectService.shared.play(.click)
    }

    private func finishIconLaunchWait(for game: PortedGame, rerun: Bool, outcome: Result<Bool, Error>) {
        guard iconLaunchWait.gameID == game.id, !rerun else { return }
        let noticeID = iconLaunchWait.noticeID
        let succeeded: Bool
        if case .success = outcome { succeeded = true } else { succeeded = false }
        let launchID = iconLaunchWait.finished(gameID: game.id, rerun: false, succeeded: succeeded,
                                               visibleNoticeID: settingsNotice?.id)
        if launchingGameId == game.id { launchingGameId = nil }
        if settingsNotice?.id == noticeID {
            settingsNotice = nil
            if case .failure(let error) = outcome {
                showSettingsNotice(title: L10n.text("Could not prepare the game"), message: error.localizedDescription)
            }
        }
        if let launchID, let current = libraryGames.first(where: { $0.id == launchID }) {
            // Recheck the current app, saves and running state, as for any Play request.
            launchGame(current)
        }
    }

    /// The pop-up's answer: show the player's Icon on the app too, or keep the game's own.
    public func setUsesPickedAppIcon(_ use: Bool, for game: PortedGame) {
        guard authorizeDevelopmentOperation(.icon, game: game) else { return }
        updateAppIconState(game) {
            $0.usesPickedAppIcon = use
            $0.appIconOnMac = use
            $0.appIconPending = true
        }
        syncPendingAppIcons()
    }

    /// Automatic removes the personal image without changing the player's destination choice.
    public func appIconPickChanged(for game: PortedGame, removed: Bool) {
        guard authorizeDevelopmentOperation(.icon, game: game) else { return }
        updateAppIconState(game) {
            if removed { $0.useAutomaticAppIcon() }
            $0.appIconPending = true
        }
        syncPendingAppIcons()
    }

    /// After a library scan: an app whose icon differs from what the rule wants (a pick chosen while the app was
    /// elsewhere or missing, an app moved or built again, a change lost to a crash) is put right.
    public func reconcileAppIcons() {
        guard !AppData.profile.isDevelopment else { return }
        for game in libraryGames where !game.appIconPending && !appIconsInFlight.contains(game.id) {
            guard let app = installedApp(game) else { continue }
            let writer = Self.appIconWriter
            let hasPick = ArtworkPicks.shared.url(titleID: iconKey(game), slot: .icon) != nil
            let hasOriginal = writer.hasOriginalIcon(app, key: iconKey(game))
            let wantsIcon = game.wantsPickedAppIcon(hasPick: hasPick, hasOriginalIcon: hasOriginal)
                || game.wantsAutomaticAppIcon(hasPick: hasPick, hasOriginalIcon: hasOriginal)
            if wantsIcon != writer.showsWrittenIcon(app) {
                updateAppIconState(game) { $0.appIconPending = true }
            }
        }
        syncPendingAppIcons()
    }

    /// Writes or puts back every waiting icon whose game is not running and not being built. A change asked for while
    /// the same app is being signed runs again once that finishes, so the last choice wins.
    public func syncPendingAppIcons() {
        for game in libraryGames where game.appIconPending {
            guard developmentOperations.permits(.icon, gameID: game.id) else { continue }
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
            appIconsInFlight.insert(game.id)
            appIconProgress[game.id] = .updating
            let hasOriginal = writer.hasOriginalIcon(app, key: key)
            let wantsPick = game.wantsPickedAppIcon(hasPick: pick != nil, hasOriginalIcon: hasOriginal)
            let wantsAutomatic = game.wantsAutomaticAppIcon(hasPick: pick != nil, hasOriginalIcon: hasOriginal)
            let buildLog = appIconBuildLogs[game.id]
            let needsAutomaticImage = pick == nil && !hasOriginal
            if needsAutomaticImage { appIconProgress[game.id] = .searching }
            Task { @MainActor [weak self] in
                let automatic = needsAutomaticImage ? await self?.automaticIconURL(for: game) : nil
                let source: URL?
                if wantsPick { source = pick }
                else if wantsAutomatic { source = automatic }
                else { source = nil }
                self?.appIconProgress[game.id] = .updating
                // Only immutable file paths and flags cross to the signing worker. Network waits and signing
                // leave the main thread free; library/UI state is updated back on the main actor.
                let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Bool, Error> in
                    let writer = AppIconWriter()
                    do {
                        return .success(try writer.update(image: source.map { try Data(contentsOf: $0) }, app: app, key: key))
                    } catch { return .failure(error) }
                }.value
                guard let self else { return }
                self.appIconsInFlight.remove(game.id)
                let again = self.appIconRerun.remove(game.id) != nil
                if !again { self.updateAppIconState(game) { $0.appIconPending = false } }
                switch outcome {
                case .success(let changed):
                    let status: AppIconProgress
                    if needsAutomaticImage && automatic == nil { status = .unavailable }
                    else if game.appIconOnMac == false { status = .launcherOnly }
                    else if changed && source != nil { status = .updated }
                    else { status = hasOriginal ? .original : .unavailable }
                    self.appIconProgress[game.id] = again ? .updating : status
                    if changed {
                        Self.refreshIcon(of: app)
                        GameIconProvider.forget(game)
                        GameArtLoader.shared.forget(game)
                        ArtworkPicks.shared.touch()
                        self.logs.append(LogEntry(level: .info, message: L10n.format("Updated the app icon of %@.", [String(describing: (game.name))])))
                    }
                case .failure(let error):
                    self.appIconProgress[game.id] = .failed(error.localizedDescription)
                    self.logs.append(LogEntry(level: .error,
                                              message: L10n.format("Could not change the app icon of %@: %@", [String(describing: (game.name)), String(describing: (error.localizedDescription))])))
                }
                if !again, let buildLog, self.appIconBuildLogs[game.id] == buildLog,
                   let status = self.appIconProgress[game.id] {
                    self.appIconBuildLogs[game.id] = nil
                    try? status.appendToBuildLog(buildLog)
                    self.logs.append(LogEntry(level: .info, message: "\(game.name): \(status.buildMessage)"))
                }
                self.finishIconLaunchWait(for: game, rerun: again, outcome: outcome)
                if again { self.syncPendingAppIcons() }
            }
        }
    }

    private func updateAppIconState(_ game: PortedGame, _ change: (inout PortedGame) -> Void) {
        do { applyCatalog(try catalogRepository.updateNXNative(id: game.id, change)) }
        catch { reportCatalogFailure(error) }
    }

    /// Finder and the Dock read icons through Launch Services, which caches them by the bundle's date.
    private static func refreshIcon(of app: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: app.path)
        LSRegisterURL(app as CFURL, true)
        NSWorkspace.shared.noteFileSystemChanged(app.path)
    }
}
