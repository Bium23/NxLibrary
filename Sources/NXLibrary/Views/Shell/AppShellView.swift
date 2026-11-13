import SwiftUI
import AppKit
import Combine
import NXLibraryCore

public struct AppShellView: View {
    @StateObject private var viewModel: AppViewModel
    @StateObject private var router: AppRouter
    @StateObject private var settings: AppSettingsStore
    @StateObject private var playSessions = PlaySessionStore()
    @StateObject private var artwork = ArtworkStore()
    @StateObject private var runningGames = RunningGameMonitor()
    @StateObject private var sessionCard = SessionCardPresenter()
    @StateObject private var updater = AppUpdater()
    @StateObject private var sources: CatalogSourcesModel
    @StateObject private var nativeMenus = NativeMenuCommands.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var localization = AppLocalization.shared
    @State private var gestureKeyMonitor: Any?
    @State private var setupSourceEntryID: UUID?
    /// Dismisses the Close Game confirmation when its game quits by itself.
    @State private var closeGameWatch: AnyCancellable?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @MainActor init(state: AppShellState) {
        _sources = StateObject(wrappedValue: state.sources)
        _settings = StateObject(wrappedValue: state.settings)
        _viewModel = StateObject(wrappedValue: state.viewModel)
        _router = StateObject(wrappedValue: state.router)
    }

    private func updateLocale() {
        let previousLanguage = AppLocalization.shared.context.language
        AppLocalization.shared.configure(settings.settings)
        if previousLanguage != AppLocalization.shared.context.language {
            viewModel.refreshLocalizedMetadata()
        }
    }

    private var backdropStyle: SeleneBackdropStyle {
        SeleneBackdropStyle(wallpaperURL: theme.wallpaper(for: settings.settings.wallpaperID)?.url,
                            sizing: settings.settings.backgroundSizing,
                            animated: settings.settings.animatedBackground,
                            brightness: settings.settings.wallpaperBrightness)
    }

    /// Spotlight or Collection: the screens that pick a game.
    private var isHomeRoute: Bool {
        router.route == .library || router.route == .collection
    }

    /// The Close Game confirmation is open; menu commands and the dialog's input wait for it.
    private var isCloseGameOpen: Bool {
        viewModel.gameToClose != nil || viewModel.gameToRemove != nil || showsUpdateOffer || showsInstallFailure || showsSettingsNotice
    }
    private var showsInstallFailure: Bool {
        viewModel.gameWithInstallFailure != nil && !router.isIntroShowing && !viewModel.showSetupCheck
            && viewModel.launchOverlay == nil && viewModel.gameToClose == nil && viewModel.gameToRemove == nil
    }
    /// The update dialog waits for the intro and the Setup check.
    private var showsUpdateOffer: Bool {
        (updater.offer != nil || updater.isCheckPresented) && !router.isIntroShowing && !viewModel.showSetupCheck
            && !showsInstallFailure && viewModel.gameToClose == nil && viewModel.gameToRemove == nil
            && viewModel.launchOverlay == nil && !router.isScreenshotViewerOpen
    }
    private var showsSettingsNotice: Bool {
        viewModel.settingsNotice != nil && !router.isIntroShowing && !viewModel.showSetupCheck
            && !router.isScreenshotViewerOpen && viewModel.launchOverlay == nil
            && viewModel.gameToClose == nil && viewModel.gameToRemove == nil
            && !showsInstallFailure && !showsUpdateOffer
    }

    private var reduceMotion: Bool {
        settings.settings.reduceMotion || accessibilityReduceMotion
    }

    private var nativeMenuAvailability: NativeMenuAvailability {
        let general = !router.isIntroShowing && !viewModel.showSetupCheck
            && !isCloseGameOpen && !router.isScreenshotViewerOpen && !router.isSearchPresented
            && !viewModel.isGameOptionsOpen && viewModel.launchOverlay == nil && NSApp.modalWindow == nil
            && NSApp.keyWindow?.attachedSheet == nil && NSApp.keyWindow?.isSheet != true
        let game = general && !router.isMenuPresented ? viewModel.currentFocusedGame : nil
        let focused = general && !router.isMenuPresented ? viewModel.currentFocusedCatalogGame : nil
        let steam = focused?.integration == .steam ? focused : nil
        // A Steam game's details are its Spotlight page; it has no separate Details screen.
        let catalog = viewModel.currentFocusedCatalogGame
        return NativeMenuAvailability(general: general,
            play: game?.isPlayableLocally == true || steam.map(SteamPlayCoordinator.shared.canPlay) == true,
            details: isHomeRoute && catalog != nil && (catalog?.integration != .steam || router.route == .library),
            options: game != nil || steam != nil,
            catalogRecovery: general && !viewModel.isBuilding && !viewModel.catalogBuildRecoveries.isEmpty)
    }

    /// The launch screen sits over everything, menu included, until the game's window shows.
    @ViewBuilder private var launchLayer: some View {
        if router.isIntroShowing {
            IntroView(settings: settings, reduceMotion: reduceMotion) { router.isIntroShowing = false }
        } else if let state = viewModel.launchOverlay {
            LaunchScreenView(state: state, viewModel: viewModel, artwork: artwork,
                             settings: settings.settings, reduceMotion: reduceMotion)
                .id(state.game.id)
        }
    }

    /// Game options, Add game and the console open and close alike: a fade with a slight scale.
    private var overlayTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985))
    }

    /// The screen plus the overlays that sit on it; split from `body` for the type checker.
    private var layers: some View {
        ZStack {
            SeleneTheme.scrim.ignoresSafeArea()
            content
                // Game options, Add game and the console blur the screen behind instead of darkening it.
                .blur(radius: !viewModel.isGameOptionsOpen && !router.route.isOverlay ? 0 : 10)
                .allowsHitTesting(!router.route.isOverlay && !viewModel.isGameOptionsOpen)
            if router.route == .addGame {
                AddGameView(viewModel: viewModel,
                            router: router,
                            artwork: artwork,
                            showsHints: settings.settings.showButtonHints,
                            reviewSelectionID: setupSourceEntryID)
                    .allowsHitTesting(!viewModel.showSetupCheck)
                    .transition(overlayTransition)
                    .zIndex(0.8)
            }
            if router.route == .console {
                ConsoleView(viewModel: viewModel, router: router,
                            showsHints: settings.settings.showButtonHints)
                    .transition(overlayTransition)
                    .zIndex(0.8)
            }
            if router.isSearchPresented && isHomeRoute {
                FindGameView(router: router, viewModel: viewModel, playSessions: playSessions,
                             artwork: artwork)
                    .transition(.opacity)
                    .zIndex(0.5)
            }
            if viewModel.showSetupCheck {
                Group {
                    if viewModel.firstRunSetup.page == .games {
                        YourGamesSetupView(viewModel: viewModel,
                                           onChooseFiles: { chooseFirstGame(usingFolder: false) },
                                           onChooseFolder: { chooseFirstGame(usingFolder: true) },
                                           onFinish: {
                                               viewModel.completeSetup()
                                               router.navigate(to: .library)
                                           })
                    } else {
                        SetupCheckView(viewModel: viewModel, isFirstRun: !viewModel.setupCompleted)
                    }
                }
                    .transition(.opacity)
                    .zIndex(2.5)
            }
            if let game = viewModel.gameToClose {
                closeGameOverlay(game)
                    .transition(.opacity)
                    .zIndex(3)
            }
            if let game = viewModel.gameToRemove {
                removeGameOverlay(game)
                    .transition(.opacity)
                    .zIndex(3)
            }
            if showsUpdateOffer {
                updateOfferOverlay()
                    .transition(.opacity)
                    .zIndex(3)
            }
            if showsInstallFailure, let game = viewModel.gameWithInstallFailure {
                installFailureOverlay(game)
                    .transition(.opacity)
                    .zIndex(3)
            }
            if showsSettingsNotice, let notice = viewModel.settingsNotice {
                settingsNoticeOverlay(notice)
                    .transition(.opacity)
                    .zIndex(4)
            }
            if router.isMenuPresented {
                if router.isThemePickerOpen {
                    ThemePickerView(viewModel: viewModel, router: router, settings: settings, games: viewModel.libraryGames)
                        .transition(.opacity)
                        .zIndex(1)
                } else {
                    MenuOverlayView(
                        router: router,
                        onSelect: { runMenuAction($0) },
                        onSelectPower: { runPower($0) }
                    )
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            if let game = viewModel.gameForSettingsSheet {
                GameOptionsView(
                    viewModel: viewModel,
                    game: game,
                    origin: viewModel.gameOptionsOrigin,
                    onClose: { viewModel.gameForSettingsSheet = nil },
                    onShowBuild: {
                        viewModel.gameForSettingsSheet = nil
                        router.openAddGame()
                    },
                    onMove: {
                        viewModel.gameForSettingsSheet = nil
                        router.requestSpotlightMove(SpotlightItem.game(game.id).key)
                    },
                    opensMods: viewModel.gameOptionsOpensMods
                )
                .transition(overlayTransition)
                .zIndex(2)
            }
            if let game = viewModel.steamOptionsGame {
                SteamOptionsView(
                    viewModel: viewModel,
                    game: game,
                    origin: viewModel.gameOptionsOrigin,
                    onClose: { viewModel.steamOptionsGame = nil },
                    onMove: {
                        viewModel.steamOptionsGame = nil
                        router.requestSpotlightMove(SpotlightItem.game(game.id).key)
                    }
                )
                .id(game.id)
                .transition(overlayTransition)
                .zIndex(2)
            }
        }
    }

    /// Layers with environment, sheets and lifecycle; split from `body` for the type checker.
    private var styled: some View {
        layers
        .allowsHitTesting(!nativeMenus.isTracking)
        .background(FullscreenCursorView())
        .background(StartupWindowView(fullscreen: settings.settings.startInFullscreen))
        .focusedSceneValue(\.nxMenuAvailability, nativeMenuAvailability)
        .overlay {
            SessionCardLayer(presenter: sessionCard, games: viewModel.libraryGames,
                             metadata: viewModel.storeMetadata, artwork: artwork)
        }
        .overlay { launchLayer }
        .modifier(SoundCueHooks(router: router, viewModel: viewModel))
        // Inside the canvas root so the sheet inherits the window's canvas units.
        .seleneCanvasRoot()
        .animation(reduceMotion ? nil : SeleneTheme.screen,
                   value: viewModel.optionsGameID)
        .animation(reduceMotion ? nil : SeleneTheme.quick,
                   value: router.isMenuPresented)
        .animation(reduceMotion ? nil : SeleneTheme.screen, value: router.isThemePickerOpen)
        .animation(SeleneTheme.quick, value: router.isSearchPresented)
        .animation(reduceMotion ? nil : SeleneTheme.screen, value: viewModel.showSetupCheck)
        .animation(reduceMotion ? nil : SeleneTheme.screen, value: viewModel.firstRunSetup.page)
        .animation(reduceMotion ? nil : SeleneTheme.screen, value: router.route == .addGame)
        .animation(reduceMotion ? nil : SeleneTheme.screen, value: router.route == .console)
        .animation(reduceMotion ? nil : SeleneTheme.quick,
                   value: viewModel.gameToClose?.id)
        .animation(reduceMotion ? nil : SeleneTheme.quick,
                   value: viewModel.gameToRemove?.id)
        .animation(reduceMotion ? nil : SeleneTheme.quick,
                   value: viewModel.gameWithInstallFailure?.id)
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: viewModel.settingsNotice?.id)
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: showsUpdateOffer)
        .environment(\.seleneReduceMotion, reduceMotion)
        .environment(\.seleneBackdropStyle, backdropStyle)
        .environment(\.seleneShowButtonHints, settings.settings.showButtonHints)
        .environment(\.seleneButtonNames, settings.settings.buttonNames)
        .environmentObject(updater)
        .environmentObject(sources)
        .onAppear { sources.startIfEnabled() }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1100, minHeight: 700)
        .onAppear(perform: startRuntime)
        .onReceive(settings.$loadError) { error in
            guard error != nil else { return }
            let writing = settings.errorKind == .writing
            viewModel.showSettingsNotice(
                title: writing ? L10n.text("Settings not saved") : L10n.text("Settings unavailable"),
                message: writing ? L10n.text("Your changes could not be saved. Try again.")
                    : L10n.text("Defaults are in use. Your previous settings file has been kept."),
                retry: writing ? { _ = settings.save() } : nil)
            viewModel.settingsNotice?.onDismiss = { settings.dismissError() }
        }
        .onDisappear {
            runningGames.stop()
            SteamPlayCoordinator.shared.stop()
            removeGestureKeyMonitor()
        }
        .onChange(of: viewModel.libraryGames) { games in
            runningGames.setGames(games)
        }
        .onChange(of: viewModel.catalogGames) { games in
            SteamPlayCoordinator.shared.setGames(games, sources: viewModel.catalogSourceConfigurations)
        }
        .onChange(of: viewModel.catalogSourceConfigurations) { sources in
            SteamPlayCoordinator.shared.setGames(viewModel.catalogGames, sources: sources)
        }
        .onReceive(runningGames.$endedSession) { summary in
            sessionCard.ended(summary, enabled: settings.settings.showsSessionCard)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            sessionCard.becameActive()
        }
        .onChange(of: settings.settings.showsSessionCard) { on in
            if !on { sessionCard.clear() }
        }
        .onChange(of: showsUpdateOffer) { viewModel.isUpdateOfferOpen = $0 }
        .onChange(of: router.route) { route in
            recordLastHome(route)
            switch route {
            case .addGame:
                viewModel.addGameDidBecomeVisible(
                    defaults: settings.settings.gameDefaults,
                    returningFromBack: router.isReturningFromBack,
                    preservingSelection: setupSourceEntryID != nil
                )
            case .library, .collection, .detail:
                setupSourceEntryID = nil
                viewModel.addGameDidLeave()
            default:
                break
            }
        }
    }

    private var nativeGameCommands: some View {
        styled
        .environment(\.locale, localization.context.formatLocale)
        .environment(\.nxAppLocale, localization.context)
        .environment(\.catalogPersonalizations, viewModel.personalizations)
        .onChange(of: settings.settings.appLanguage) { _ in updateLocale() }
        .onChange(of: settings.settings.appRegion) { _ in updateLocale() }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryPlayFocused)) { _ in
            guard !router.isMenuPresented,
                  nativeMenuAvailability.play,
                  !viewModel.isGameOptionsOpen,
                  !isCloseGameOpen else { return }
            if let steam = viewModel.currentFocusedCatalogGame, steam.integration == .steam {
                SteamPlayCoordinator.shared.press(steam)
            } else if let game = viewModel.currentFocusedGame {
                viewModel.launchGame(game)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenDetails)) { _ in
            guard !router.isMenuPresented,
                  !viewModel.isGameOptionsOpen,
                  !isCloseGameOpen,
                  isHomeRoute,
                  let game = viewModel.currentFocusedCatalogGame else { return }
            if router.route == .library { viewModel.spotlight.showGameDetails() }
            else if game.integration != .steam { router.showDetail(game.id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenGameOptions)) { _ in
            guard nativeMenuAvailability.options else { return }
            switch router.route {
            case .library, .collection:
                let origin: GameOptionsOrigin = router.route == .library ? .spotlight : .collection
                if let steam = viewModel.currentFocusedCatalogGame, steam.integration == .steam {
                    viewModel.openSteamOptions(steam, from: origin)
                } else if let game = viewModel.currentFocusedGame {
                    viewModel.openGameOptions(game, from: origin)
                }
            case .detail(let id):
                if let game = viewModel.libraryGames.first(where: { $0.id == id }) {
                    viewModel.openGameOptions(game, from: .details)
                }
            default:
                break
            }
        }
    }

    public var body: some View {
        nativeGameCommands
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryCheckAppUpdates)) { _ in
            guard nativeMenuAvailability.general else { return }
            router.closeMenu()
            updater.checkNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenMenu)) { _ in
            guard !isCloseGameOpen, !viewModel.isGameOptionsOpen, !router.isScreenshotViewerOpen else { return }
            router.isMenuPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenSettings)) { _ in
            guard !isCloseGameOpen, !router.isScreenshotViewerOpen, !viewModel.isGameOptionsOpen else { return }
            router.closeMenu()
            router.openSettings(.startUp)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryRetryCatalogSave)) { _ in
            guard nativeMenuAvailability.catalogRecovery else { return }
            viewModel.retrySavingBuildResults()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenConsole)) { _ in
            guard !isCloseGameOpen, !router.isScreenshotViewerOpen, !viewModel.isGameOptionsOpen else { return }
            router.closeMenu()
            router.openConsole()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryPortingNoticeOpened)) { note in
            guard !isCloseGameOpen, !router.isScreenshotViewerOpen, !viewModel.isGameOptionsOpen,
                  let id = (note.userInfo?["gameID"] as? String).flatMap(UUID.init(uuidString:)) else { return }
            router.closeMenu()
            if note.userInfo?["outcome"] as? String == "failed" {
                viewModel.lastBuildGameID = id
                viewModel.reviewsFailureOnAddGame = true
                if router.route == .addGame {
                    viewModel.addGameDidBecomeVisible(defaults: settings.settings.gameDefaults, returningFromBack: false)
                } else {
                    router.openAddGame()
                }
            } else {
                router.showLibrary()
                router.requestSpotlightSelect(id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenLibrary)) { _ in
            guard !isCloseGameOpen, !router.isScreenshotViewerOpen, !viewModel.isGameOptionsOpen else { return }
            router.closeMenu()
            router.showLibrary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenAddGame)) { _ in
            guard !isCloseGameOpen, !router.isMenuPresented, !router.isScreenshotViewerOpen,
                  !viewModel.isGameOptionsOpen else { return }
            router.closeMenu()
            openFreshAddGame()
        }
        .onExitCommand {
            if router.isScreenshotViewerOpen {
                // The viewer's key monitor closes it.
            } else if showsSettingsNotice {
                finishSettingsNotice(choice: 0)
            } else if showsInstallFailure {
                viewModel.gameWithInstallFailure = nil
            } else if viewModel.gameToClose != nil {
                viewModel.dismissCloseGame()
            } else if viewModel.gameToRemove != nil {
                viewModel.dismissRemoveGame()
            } else if showsUpdateOffer {
                updater.later()
            } else if viewModel.isGameOptionsOpen {
                // Game options steps back (dialog, then Edit details) or closes.
                NotificationCenter.default.post(name: .nxGameOptionsGamepadAction, object: GamepadAction.cancel)
            } else if router.isMenuPresented {
                menuInput(.cancel)
            } else if router.isSearchPresented {
                // FindGameView's key monitor closes it.
            } else if isHomeRoute {
                router.isMenuPresented = true
            } else if case .settings = router.route {
                // SettingsView handles its own Esc.
            } else if case .addGame = router.route {
                // AddGameView handles its own Esc.
            } else if case .console = router.route {
                // ConsoleView handles its own Esc.
            } else {
                router.back()
            }
        }
        .onChange(of: viewModel.alertMessage) { _ in
            presentLegacyNotice()
        }
        .onChange(of: viewModel.settingsNotice?.id) { id in
            if id == nil { presentLegacyNotice() }
        }
    }

    /// The current screen; under Add game or the console, the screen they were opened from.
    @ViewBuilder
    private var content: some View {
        switch router.route.isOverlay ? router.underlyingRoute : router.route {
        case .library:
            SpotlightView(
                viewModel: viewModel,
                router: router,
                settings: settings,
                playSessions: playSessions,
                runningGames: runningGames,
                artwork: artwork
            )
        case .collection:
            CollectionView(
                viewModel: viewModel,
                router: router,
                settings: settings,
                playSessions: playSessions,
                artwork: artwork
            )
        case .detail(let id):
            if let game = viewModel.libraryGames.first(where: { $0.id == id }) {
                GameDetailView(
                    viewModel: viewModel,
                    router: router,
                    settings: settings,
                    playSessions: playSessions,
                    runningGames: runningGames,
                    artwork: artwork,
                    game: game
                )
            } else {
                Color.clear
                    .onAppear { router.showLibrary() }
            }
        case .settings(let section):
            SettingsView(initialSection: section,
                         viewModel: viewModel,
                         settings: settings,
                         router: router,
                         artwork: artwork)
        case .addGame:
            // Never the underlying route; Add game is drawn over `content`.
            Color.clear
        case .console:
            // Never the underlying route; the console is drawn over `content`.
            Color.clear
        }
    }

    private func startRuntime() {
        presentLegacyNotice()
        viewModel.playSessionStore = playSessions
        viewModel.settingsStore = settings
        SoundEffectService.shared.bind(to: settings)
        artwork.trimCache()
        viewModel.refreshBoxArtIndex()
        if settings.settings.checkEngineAtLaunch && !AppData.profile.isDevelopment { SetupCheckModel.checkAtLaunch(viewModel: viewModel) }
        runningGames.start(sessions: playSessions)
        runningGames.setGames(viewModel.libraryGames)
        // After the nxnative reconcile, which closes a Steam session left by a restart at its last heartbeat.
        SteamPlayCoordinator.shared.setGames(viewModel.catalogGames, sources: viewModel.catalogSourceConfigurations)
        SteamPlayCoordinator.shared.start(sessions: playSessions)
        viewModel.installPendingBuilds()
        viewModel.syncPendingAppIcons()
        closeGameWatch = runningGames.$runningGameIDs.sink { [weak viewModel] ids in
            guard let viewModel else { return }
            viewModel.runningGameCount = ids.count
            // A game that quit lets the build that waited for it go in (after this change is published).
            DispatchQueue.main.async {
                viewModel.installPendingBuilds()
                // An icon chosen while the game ran goes on once it quits.
                viewModel.syncPendingAppIcons()
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
                return L10n.format("After you quit %@", [String(describing: (name))])
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
            guard !nativeMenus.isTracking else { return }
            if router.isIntroShowing {
                // Any controller input skips the intro.
                NotificationCenter.default.post(name: .nxIntroSkip, object: nil)
                return
            }
            if viewModel.showSetupCheck {
                // The Setup check owns the controller; Menu does nothing there (as in Selene).
                NotificationCenter.default.post(name: .nxSetupCheckGamepadAction, object: action)
                return
            }
            if showsSettingsNotice {
                settingsNoticeInput(action)
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

    // MARK: - Retry a ready build

    private func settingsNoticeOverlay(_ notice: SettingsNotice) -> some View {
        ZStack {
            SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { finishSettingsNotice(choice: 0) }
            SeleneChoiceDialog(title: notice.title, message: notice.message,
                               choices: notice.retry == nil ? [notice.cancelTitle] : [notice.cancelTitle, notice.actionTitle],
                               focus: $viewModel.settingsNoticeFocus,
                               onChoose: { finishSettingsNotice(choice: $0) })
        }
    }

    private func finishSettingsNotice(choice: Int) {
        let notice = viewModel.settingsNotice
        viewModel.settingsNotice = nil
        notice?.onDismiss?()
        if choice == 1 { notice?.retry?() }
        presentLegacyNotice()
    }

    private func presentLegacyNotice() {
        guard viewModel.settingsNotice == nil, let message = viewModel.alertMessage else { return }
        viewModel.alertMessage = nil
        viewModel.showSettingsNotice(title: L10n.text("NX Library"), message: message)
    }

    private func settingsNoticeInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft: viewModel.settingsNoticeFocus = 0
        case .navigateRight: viewModel.settingsNoticeFocus = viewModel.settingsNotice?.retry == nil ? 0 : 1
        case .confirm: finishSettingsNotice(choice: viewModel.settingsNoticeFocus)
        case .cancel: finishSettingsNotice(choice: 0)
        default: break
        }
    }

    private func installFailureOverlay(_ game: PortedGame) -> some View {
        let app = game.pendingInstall?.finalApp ?? game.url
        let currentExists = FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path)
        return ZStack {
            SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { viewModel.gameWithInstallFailure = nil }
            SeleneConfirmDialog(title: L10n.text("Installation failed"),
                                message: L10n.format("The new build of %@ has been kept.", [String(describing: (game.name))])
                                    + (currentExists ? L10n.text("\nYour current app is still available.") : L10n.text("\nYou can retry installation.")),
                                confirmTitle: "Retry", cancelTitle: L10n.text("Close"),
                                focus: $viewModel.installFailureFocus,
                                onCancel: { viewModel.gameWithInstallFailure = nil },
                                onConfirm: { viewModel.retryFailedInstallation() })
        }
    }

    private func installFailureInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let next: SeleneConfirmButton = action == .navigateLeft ? .cancel : .confirm
            if viewModel.installFailureFocus != next {
                viewModel.installFailureFocus = next
                SoundEffectService.shared.play(.focus)
            }
        case .confirm:
            if viewModel.installFailureFocus == .confirm {
                viewModel.retryFailedInstallation()
            } else {
                viewModel.gameWithInstallFailure = nil
            }
        case .cancel: viewModel.gameWithInstallFailure = nil
        default: break
        }
    }

    // MARK: - Close Game confirmation

    private func closeGameOverlay(_ game: PortedGame) -> some View {
        ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { viewModel.dismissCloseGame() }
            SeleneConfirmDialog(title: L10n.format("Close %@?", [String(describing: (game.name))]),
                                message: L10n.text("Unsaved progress in the game will be lost."),
                                confirmTitle: "Close",
                                focus: $viewModel.closeGameFocus,
                                onCancel: { viewModel.dismissCloseGame() },
                                onConfirm: confirmCloseGame)
        }
    }

    /// Input while the Close Game confirmation is open: Left and Right pick a pill, A runs it, B cancels.
    private func closeGameInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let next: SeleneConfirmButton = action == .navigateLeft ? .cancel : .confirm
            if viewModel.closeGameFocus != next {
                viewModel.closeGameFocus = next
                SoundEffectService.shared.play(.focus)
            }
        case .confirm:
            if viewModel.closeGameFocus == .confirm {
                confirmCloseGame()
            } else {
                viewModel.dismissCloseGame()
            }
        case .cancel:
            viewModel.dismissCloseGame()
        default:
            break
        }
    }

    // MARK: - Delete after a failed porting

    private func removeGameOverlay(_ game: PortedGame) -> some View {
        ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { viewModel.dismissRemoveGame() }
            SeleneConfirmDialog(title: L10n.format("Delete %@?", [String(describing: (game.name))]),
                                message: L10n.text("It leaves the library. Your game files and the build cache stay on disk."),
                                confirmTitle: "Delete",
                                focus: $viewModel.removeGameFocus,
                                onCancel: { viewModel.dismissRemoveGame() },
                                onConfirm: { viewModel.confirmRemoveGame() })
        }
    }

    // MARK: - A newer release at launch

    private func updateOfferOverlay() -> some View {
        ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { updater.later() }
            AppUpdateDialog(updater: updater, requirementNotes: updater.dialogRelease.map {
                AppUpdate.requirementNotes($0.requirements,
                    installedXcode: viewModel.environmentStatus?.xcodeVersion,
                    currentEngine: viewModel.pinnedEngineCommit)
            } ?? [], blockedReason: updater.blockedReason())
        }
    }

    private func updateOfferInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let next: SeleneConfirmButton = action == .navigateLeft && updater.dialogHasSecondaryButton ? .cancel : .confirm
            if updater.offerFocus != next {
                updater.offerFocus = next
                SoundEffectService.shared.play(.focus)
            }
        case .confirm:
            SoundEffectService.shared.play(.click)
            if updater.offerFocus == .confirm { updater.confirmDialog() } else { updater.later() }
        case .cancel:
            updater.later()
        case .navigateUp, .navigateDown, .jumpToStart, .jumpToEnd:
            let last = max(0, (updater.dialogRelease?.notes.components(separatedBy: "\n").count ?? 1) - 1)
            switch action {
            case .jumpToStart: updater.notesScroll = 0
            case .jumpToEnd: updater.notesScroll = last
            default: updater.notesScroll = min(last, max(0, updater.notesScroll + (action == .navigateUp ? -3 : 3)))
            }
        default:
            break
        }
    }

    private func removeGameInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let next: SeleneConfirmButton = action == .navigateLeft ? .cancel : .confirm
            if viewModel.removeGameFocus != next {
                viewModel.removeGameFocus = next
                SoundEffectService.shared.play(.focus)
            }
        case .confirm:
            SoundEffectService.shared.play(.click)
            if viewModel.removeGameFocus == .confirm {
                viewModel.confirmRemoveGame()
            } else {
                viewModel.dismissRemoveGame()
            }
        case .cancel:
            viewModel.dismissRemoveGame()
        default:
            break
        }
    }

    private func confirmCloseGame() {
        guard let game = viewModel.gameToClose else { return }
        viewModel.dismissCloseGame()
        SoundEffectService.shared.play(.click)
        runningGames.close(game)
    }

    /// App-level monitor for the keyboard equivalents of the controller gestures.
    /// Handles only Tab, Cmd+F, Cmd+, , Home and End; every other event passes through.
    private func installGestureKeyMonitor() {
        guard gestureKeyMonitor == nil else { return }
        gestureKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [router, viewModel] event in
            if nativeMenus.isTracking { return event }
            // The screenshot viewer owns the keyboard (its own monitor handles it); no navigating underneath.
            if router.isScreenshotViewerOpen { return event }
            // The intro's own monitor takes any key as "skip".
            if router.isIntroShowing { return event }
            // An alert or another window's sheet owns Return and Esc.
            if viewModel.alertMessage != nil || NSApp.modalWindow != nil
                || event.window?.attachedSheet != nil || event.window?.isSheet == true {
                return event
            }
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            // The Setup check takes the keyboard: arrows, Return, Space and Esc go to it.
            if viewModel.showSetupCheck {
                guard mods.isEmpty, !(event.window?.firstResponder is NSText) else { return event }
                let setupAction: GamepadAction?
                switch event.keyCode {
                case 123: setupAction = .navigateLeft
                case 124: setupAction = .navigateRight
                case 125: setupAction = .navigateDown
                case 126: setupAction = .navigateUp
                case 36, 76, 49: setupAction = .confirm
                case 53: setupAction = .cancel
                default: setupAction = nil
                }
                guard let setupAction else { return nil }
                GameControllerService.shared.onAction?(setupAction)
                return nil
            }
            // The Close Game and Delete confirmations take the keyboard: arrows, Return, Space and Esc go to them.
            if viewModel.gameToClose != nil || viewModel.gameToRemove != nil || showsUpdateOffer || showsInstallFailure || showsSettingsNotice, mods.isEmpty {
                let closeAction: GamepadAction?
                switch event.keyCode {
                case 123: closeAction = .navigateLeft
                case 124: closeAction = .navigateRight
                case 125: closeAction = showsUpdateOffer ? .navigateDown : nil
                case 126: closeAction = showsUpdateOffer ? .navigateUp : nil
                case 36, 76, 49: closeAction = .confirm
                case 53: closeAction = .cancel
                default: closeAction = nil
                }
                if let closeAction {
                    GameControllerService.shared.onAction?(closeAction)
                    return nil
                }
            }
            // The open control center takes the keyboard: arrows, Return, Space and Esc go to the menu,
            // and no screen underneath sees them.
            // Typing in a menu's text field (the Theme screen's search): keys go to the field, Esc leaves it.
            if router.isMenuPresented, event.window?.firstResponder is NSText, event.keyCode != 53 {
                return event
            }
            if router.isMenuPresented, mods.isEmpty {
                let menuAction: GamepadAction?
                switch event.keyCode {
                case 123: menuAction = .navigateLeft     // Left arrow
                case 124: menuAction = .navigateRight    // Right arrow
                case 125: menuAction = .navigateDown     // Down arrow
                case 126: menuAction = .navigateUp       // Up arrow
                case 36, 76, 49: menuAction = .confirm   // Return, keypad Enter, Space
                case 53: menuAction = .cancel            // Esc
                case 51: menuAction = router.isThemePickerOpen ? .contextAction : nil   // Delete: remove your own wallpaper
                case 12: menuAction = router.isThemePickerOpen ? .tabPrevious : nil     // Q: Wallpapers / Live, as LB
                case 14: menuAction = router.isThemePickerOpen ? .tabNext : nil         // E: as RB
                case 7: menuAction = router.isThemePickerOpen ? .secondaryAction : nil  // X: open the page
                case 16: menuAction = router.isThemePickerOpen ? .contextAction : nil   // Y: remove
                default: menuAction = nil
                }
                if let menuAction {
                    GameControllerService.shared.onAction?(menuAction)
                    return nil
                }
            }
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let typing = event.window?.firstResponder is NSText
            var action: GamepadAction?
            switch (event.keyCode, key, mods) {
            case (48, _, []):                       // Tab
                if typing { return event }
                action = .view
            case (_, "f", [.command]):              // Cmd+F
                if typing { return event }
                action = .viewHold
            case (_, ",", [.command]):              // Cmd+,
                // Same as holding Menu. Consumed, so the menu-bar Settings command does not open Settings a second time.
                action = .menuHold
            case (115, _, []):                      // Home
                if typing { return event }
                action = .jumpToStart
            case (119, _, []):                      // End
                if typing { return event }
                action = .jumpToEnd
            default:
                return event
            }
            if let action { GameControllerService.shared.onAction?(action) }
            return nil
        }
    }

    private func removeGestureKeyMonitor() {
        if let monitor = gestureKeyMonitor { NSEvent.removeMonitor(monitor) }
        gestureKeyMonitor = nil
    }

    /// Input while the control center is open: arrows move, A selects, B (or Esc) closes the Power pills
    /// first and then the menu, Menu closes it, and hold Menu closes it and opens Settings.
    private func menuInput(_ action: GamepadAction) {
        // The Theme screen takes everything but Menu, which closes the whole menu.
        if router.isThemePickerOpen, action != .menu, action != .menuHold {
            NotificationCenter.default.post(name: .nxThemePickerGamepadAction, object: action)
            return
        }
        switch action {
        case .navigateLeft:
            router.moveMenu(by: -1)
        case .navigateRight:
            router.moveMenu(by: 1)
        case .navigateUp:
            router.movePowerMenu(by: -1)
        case .navigateDown:
            router.movePowerMenu(by: 1)
        case .confirm:
            if router.menuSelection.isPowerOpen {
                runPower(router.menuSelection.power)
            } else {
                runMenuAction(router.menuSelection.selected)
            }
        case .cancel:
            if router.menuSelection.isPowerOpen {
                router.closePowerMenu()
            } else {
                router.closeMenu()
            }
        case .menu:
            router.closeMenu()
        case .menuHold:
            router.closeMenu()
            router.openSettings(.startUp)
        default:
            break
        }
    }

    /// A row button. The menu closes before it navigates; Power only opens or closes its
    /// pills, and Theme opens its screen in place of the row.
    private func runMenuAction(_ action: MenuAction) {
        switch action {
        case .power:
            if router.menuSelection.isPowerOpen {
                router.closePowerMenu()
            } else {
                router.openPowerMenu()
            }
        case .addGame:
            router.closeMenu()
            openFreshAddGame()
        case .refreshLibrary:
            router.closeMenu()
            viewModel.refreshLibrary()
            if sources.configuration.isEnabled { sources.refresh() }
        case .manageSources:
            router.closeMenu()
            router.openSettings(.sources)
        case .settings:
            router.closeMenu()
            router.openSettings(.startUp)
        case .theme:
            // The menu's own screen: the theme's colors, then the background.
            router.isThemePickerOpen = true
        case .console:
            router.closeMenu()
            router.openConsole()
        case .setupCheck:
            router.closeMenu()
            viewModel.reopenSetup()
        }
    }

    private func runPower(_ action: PowerAction) {
        switch action {
        case .quit:
            router.closeMenu()
            NSApplication.shared.terminate(nil)
        case .hide:
            router.closeMenu()
            NSApplication.shared.hide(nil)
        case .relaunch:
            relaunchApp()
        }
    }

    /// Starts a helper that waits for this process to exit and then opens the bundle again, then quits.
    /// A second instance cannot be opened while this one runs (LSMultipleInstancesProhibited), so
    /// the new one must start after this one has gone.
    private func relaunchApp() {
        router.closeMenu()
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c",
            "i=0; while kill -0 \"$1\" 2>/dev/null && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done; exec /usr/bin/open \"$2\"",
            "relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundleURL.path
        ]
        do {
            try helper.run()
        } catch {
            viewModel.alertMessage = L10n.format("NX Library could not restart: %@", [String(describing: (error.localizedDescription))])
            return
        }
        NSApplication.shared.terminate(nil)
    }

    /// Remembers which home screen was used last, for Start on → Last used.
    private func recordLastHome(_ route: AppRoute) {
        let home: StartScreen
        switch route {
        case .library: home = .spotlight
        case .collection: home = .collection
        default: return
        }
        if settings.settings.lastHome != home { settings.settings.lastHome = home }
    }

    private func chooseFirstGame(usingFolder: Bool) {
        guard viewModel.showSetupCheck,
              viewModel.firstRunSetup.page == .games else { return }
        let defaults = settings.settings.gameDefaults
        let picked = usingFolder ? viewModel.selectGameFolder(startingNewGameWith: defaults)
            : viewModel.selectGameFiles(startingNewGameWith: defaults)
        guard picked else { return }
        setupSourceEntryID = UUID()
        viewModel.completeSetup()
        router.openAddGame()
    }

    private func openFreshAddGame() {
        if router.route == .addGame, !viewModel.isBuilding {
            viewModel.startNewAddGame(defaults: settings.settings.gameDefaults)
        } else {
            router.openAddGame()
        }
    }
}

/// Selene's panel and back cues for the shell's overlays and routes.
private struct SoundCueHooks: ViewModifier {
    @ObservedObject var router: AppRouter
    @ObservedObject var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .nxSeleneImportFinished)) { _ in
                ThemeStore.shared.reloadWallpapers()
            }
            .onChange(of: router.isMenuPresented) { open in
                SoundEffectService.shared.play(open ? .openPanel : .back)
            }
            .onChange(of: viewModel.optionsGameID) { id in
                SoundEffectService.shared.play(id == nil ? .back : .openPanel)
            }
            .onChange(of: viewModel.gameToClose?.id) { id in
                if id != nil { SoundEffectService.shared.play(.alert) }
            }
            .onChange(of: viewModel.gameToRemove?.id) { id in
                if id != nil { SoundEffectService.shared.play(.alert) }
            }
            .onChange(of: viewModel.gameWithInstallFailure?.id) { id in
                if id != nil { SoundEffectService.shared.play(.alert) }
            }
            .onChange(of: router.route) { route in
                if router.isReturningFromBack {
                    SoundEffectService.shared.play(.back)
                } else if case .settings = route {
                    SoundEffectService.shared.play(.openPanel)
                }
            }
    }
}
