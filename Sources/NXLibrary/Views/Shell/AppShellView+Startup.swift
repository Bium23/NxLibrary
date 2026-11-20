import SwiftUI
import AppKit
import Combine
import NXLibraryCore

/// What the shell starts when it appears, and the first launch's choices and the last home screen.
extension AppShellView {
    func startRuntime() {
        presentLegacyNotice()
        askToMoveIfTranslocated()
        viewModel.playSessionStore = playSessions
        viewModel.settingsStore = settings
        SoundEffectService.shared.bind(to: settings)
        // The opening's boot cue, with Spotlight's entrance (Settings → Start-up → Entrance animation).
        if settings.settings.introAnimation { SoundEffectService.shared.play(.boot) }
        artwork.trimCache()
        viewModel.refreshBoxArtIndex()
        if settings.settings.checkEngineAtLaunch && !AppData.profile.isDevelopment { SetupCheckModel.checkAtLaunch(viewModel: viewModel) }
        runningGames.start(sessions: playSessions)
        runningGames.setGames(viewModel.libraryGames)
        // Steam's playtime first: a Steam game already running starts a session at once, and trimming needs Steam's last values.
        SteamPlaytimeCoordinator.shared.setGames(viewModel.catalogGames, sources: viewModel.catalogSourceConfigurations)
        SteamPlaytimeCoordinator.shared.start(sessions: playSessions)
        SteamAchievementsStore.shared.setSources(viewModel.catalogSourceConfigurations)
        // After the nxnative reconcile, which closes a Steam session left by a restart at its last heartbeat.
        SteamPlayCoordinator.shared.setGames(viewModel.catalogGames, sources: viewModel.catalogSourceConfigurations)
        SteamPlayCoordinator.shared.nativeGames = runningGames
        SteamPlayCoordinator.shared.isLaunchScreenShowing = { [weak viewModel] in viewModel?.launchOverlay != nil }
        SteamPlayCoordinator.shared.start(sessions: playSessions, settings: settings)
        viewModel.installPendingBuilds()
        viewModel.appIcon.syncPendingAppIcons()
        closeGameWatch = runningGames.$runningGameIDs.sink { [weak viewModel] ids in
            guard let viewModel else { return }
            viewModel.runningGameCount = ids.count
            // A game that quit lets the build that waited for it go in (after this change is published).
            DispatchQueue.main.async {
                viewModel.installPendingBuilds()
                // An icon chosen while the game ran goes on once it quits.
                viewModel.appIcon.syncPendingAppIcons()
            }
            // The game under Close Game quit by itself: its confirmation has nothing left to close.
            guard let game = viewModel.gameToClose, !ids.contains(game.id) else { return }
            viewModel.dismissCloseGame()
        }
        viewModel.router = router
        updater.blockedReason = { [weak viewModel, weak runningGames] in
            guard let viewModel else { return nil }
            if viewModel.isBuilding { return L10n.text("After the porting") }
            if viewModel.isCleaningStorage { return L10n.text("After storage cleanup") }
            if viewModel.launchingGameId != nil { return L10n.text("After the game starts") }
            if viewModel.saveGate.hasActiveOperations { return L10n.text("After the save operation") }
            if let ids = runningGames?.runningGameIDs, let id = ids.first {
                let name = viewModel.libraryGames.first { $0.id == id }?.name ?? "the game"
                return L10n.format("After you quit %@", [String(describing: name)])
            }
            return nil
        }
        updater.acquireInstallLease = { [weak viewModel, weak runningGames] in
            guard let viewModel, !viewModel.isBuilding, !viewModel.isCleaningStorage, viewModel.launchingGameId == nil,
                  runningGames?.runningGameIDs.isEmpty == true,
                  let token = viewModel.saveGate.beginAppUpdate() else { return nil }
            let gate = viewModel.saveGate
            viewModel.isUpdatingApp = true
            return { [weak viewModel] in
                gate.endAppUpdate(token: token)
                viewModel?.isUpdatingApp = false
            }
        }
        updater.checkAtLaunch(enabled: settings.settings.checkAppUpdatesAtLaunch)
        installGestureKeyMonitor()
        GameControllerService.shared.onAction = { [weak viewModel, weak router] action in
            guard let viewModel, let router else { return }
            guard !nativeMenus.isTracking, !nativeDialogOwnsInput else { return }
            if viewModel.showSetupCheck {
                // The Setup check owns the controller; Menu does nothing there (as in Selene).
                NotificationCenter.default.post(name: .nxSetupCheckGamepadAction, object: action)
                return
            }
            if showsSettingsNotice {
                settingsNoticeInput(action)
                return
            }
            if showsWelcome, !showsInstallFailure, viewModel.gameToClose == nil, viewModel.gameToRemove == nil,
               !showsUpdateOffer {
                NotificationCenter.default.post(name: .nxArcaneWelcomeGamepadAction, object: action)
                return
            }
            if showsInstallFailure {
                installFailureInput(action)
                return
            }
            if viewModel.gameToClose != nil {
                closeGameInput(action)
                return
            }
            if viewModel.gameToRemove != nil {
                removeGameInput(action)
                return
            }
            if showsUpdateOffer {
                updateOfferInput(action)
                return
            }
            if router.isMenuPresented {
                menuInput(action)
                return
            }
            if viewModel.isGameOptionsOpen {
                NotificationCenter.default.post(name: .nxGameOptionsGamepadAction, object: action)
                return
            }
            if router.isSearchPresented, router.route == .library || router.route == .collection,
               action != .menu, action != .menuHold {
                NotificationCenter.default.post(name: .nxFindGameGamepadAction, object: action)
                return
            }
            if action == .menuHold {
                // Hold Menu (and Cmd+,) opens Settings from any screen.
                guard !router.isScreenshotViewerOpen else { return }
                if case .settings = router.route { return }
                router.openSettings(.startUp)
                return
            }
            switch router.route {
            case .library:
                NotificationCenter.default.post(name: .nxSpotlightGamepadAction, object: action)
            case .collection:
                NotificationCenter.default.post(name: .nxCollectionGamepadAction, object: action)
            case .detail:
                if action == .menu {
                    router.isMenuPresented = true
                } else {
                    NotificationCenter.default.post(name: .nxDetailGamepadAction, object: action)
                }
            case .settings:
                if action == .menu {
                    router.isMenuPresented = true
                } else {
                    NotificationCenter.default.post(name: .nxSettingsGamepadAction, object: action)
                }
            case .addGame:
                if action == .menu {
                    router.isMenuPresented = true
                } else {
                    NotificationCenter.default.post(name: .nxAddGameGamepadAction, object: action)
                }
            case .console:
                if action == .menu {
                    router.isMenuPresented = true
                } else {
                    NotificationCenter.default.post(name: .nxConsoleGamepadAction, object: action)
                }
            }
        }
    }

    /// Remembers which home screen was used last, for Start on → Last used.
    func recordLastHome(_ route: AppRoute) {
        let home: StartScreen
        switch route {
        case .library: home = .spotlight
        case .collection: home = .collection
        default: return
        }
        if settings.settings.lastHome != home { settings.settings.lastHome = home }
    }

    /// Open library on the first launch's `found` page; the Steam switch applies with the finish.
    func finishFromFound(importPorted: Bool) {
        guard viewModel.showSetupCheck, viewModel.firstRunSetup.page == .found else { return }
        viewModel.finishFromFound(importPorted: importPorted)
        router.navigate(to: .library)
    }

    func chooseFirstGame(usingFolder: Bool) {
        guard viewModel.showSetupCheck,
              viewModel.firstRunSetup.page == .games else { return }
        let defaults = settings.settings.gameDefaults
        let picked = usingFolder ? viewModel.porting.selectGameFolder(startingNewGameWith: defaults)
            : viewModel.porting.selectGameFiles(startingNewGameWith: defaults)
        guard picked else { return }
        setupSourceEntryID = UUID()
        viewModel.completeSetup()
        router.openAddGame()
    }

    func openFreshAddGame() {
        if router.route == .addGame, !viewModel.isBuilding {
            viewModel.porting.startNewAddGame(defaults: settings.settings.gameDefaults)
        } else {
            router.openAddGame()
        }
    }
}
