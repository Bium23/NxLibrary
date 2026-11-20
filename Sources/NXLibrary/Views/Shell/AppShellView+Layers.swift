import SwiftUI
import AppKit
import Combine
import NXLibraryCore

/// The shell's screen: its layers, overlays and modifiers, split from `body` for the type checker.
extension AppShellView {
    /// The screen plus the overlays that sit on it; split from `body` for the type checker.
    private var layers: some View {
        ZStack {
            let background = sharedBackdrop ?? SeleneBackdropRequest(style: backdropStyle, still: true)
            SeleneBackdrop(baseOpacity: background.baseOpacity, still: background.still, modsTint: background.modsTint)
                .environment(\.seleneBackdropStyle, background.style)
                .environment(\.seleneSharesBackdrop, false)
                .blur(radius: contentBlur)
            content
                // Game options, Add game and the console blur the screen behind instead of darkening it.
                .blur(radius: contentBlur)
                // Keep artwork/tiles drawn and warm, as during Spotlight's entrance, while the full page covers them.
                .opacity(fullScreenCover ? 0.001 : 1)
                .allowsHitTesting(!fullScreenCover && !router.route.isOverlay && !viewModel.isGameOptionsOpen)
            if router.route == .addGame {
                AddGameView(viewModel: viewModel,
                            router: router,
                            artwork: artwork,
                            showsHints: settings.settings.showButtonHints,
                            reviewSelectionID: setupSourceEntryID)
                    .opacity(opacityBelowCover(0.8))
                    .allowsHitTesting(!currentBackdropCover.covers(0.8))
                    .transition(overlayTransition)
                    .zIndex(0.8)
            }
            if router.route == .console {
                ConsoleView(viewModel: viewModel, router: router,
                            showsHints: settings.settings.showButtonHints)
                    .opacity(opacityBelowCover(0.8))
                    .allowsHitTesting(!currentBackdropCover.covers(0.8))
                    .transition(overlayTransition)
                    .zIndex(0.8)
            }
            if router.isSearchPresented && isHomeRoute {
                FindGameView(router: router, viewModel: viewModel, playSessions: playSessions,
                             artwork: artwork)
                    .opacity(opacityBelowCover(0.5))
                    .allowsHitTesting(!currentBackdropCover.covers(0.5))
                    .transition(.opacity)
                    .zIndex(0.5)
            }
            if viewModel.showSetupCheck {
                Group {
                    if viewModel.firstRunSetup.page == .found {
                        FoundGamesSetupView(viewModel: viewModel, steamRoot: sources.discoveryRoot) { importPorted in
                            finishFromFound(importPorted: importPorted)
                        }
                    } else if viewModel.firstRunSetup.page == .games {
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
                    .zIndex(ShellBackdropCover.setup.priority)
                    .transformPreference(SeleneBackdropRequestKey.self) { $0?.priority = ShellBackdropCover.setup.priority }
            }
            if showsWelcome {
                ArcaneWelcomeView(steamEnabled: sources.configuration.isEnabled,
                                  steamRoot: sources.discoveryRoot,
                                  appsFolder: viewModel.gameAppsFolder,
                                  onAddSteam: {
                                      sources.configure(enabled: true, root: sources.discoveryRoot)
                                  },
                                  onExit: closeWelcome)
                    .opacity(opacityBelowCover(ShellBackdropCover.welcome.priority))
                    .allowsHitTesting(!currentBackdropCover.covers(ShellBackdropCover.welcome.priority))
                    .transition(.opacity)
                    // Below Setup: a Setup check that opens after the welcome owns the input, so it is drawn on top.
                    .zIndex(ShellBackdropCover.welcome.priority)
                    .transformPreference(SeleneBackdropRequestKey.self) { $0?.priority = ShellBackdropCover.welcome.priority }
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
                Group {
                    if router.isThemePickerOpen {
                        ThemePickerView(viewModel: viewModel, router: router, settings: settings, games: viewModel.libraryGames)
                            .transition(.opacity)
                            .transformPreference(SeleneBackdropRequestKey.self) { $0?.priority = ShellBackdropCover.themePicker.priority }
                    } else {
                        MenuOverlayView(
                            router: router,
                            onSelect: { runMenuAction($0) },
                            onSelectPower: { runPower($0) }
                        )
                        .transition(.opacity)
                    }
                }
                .opacity(opacityBelowCover(ShellBackdropCover.themePicker.priority))
                .allowsHitTesting(!currentBackdropCover.covers(ShellBackdropCover.themePicker.priority))
                .zIndex(ShellBackdropCover.themePicker.priority)
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
                .opacity(opacityBelowCover(2))
                .allowsHitTesting(!currentBackdropCover.covers(2))
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
                .opacity(opacityBelowCover(2))
                .allowsHitTesting(!currentBackdropCover.covers(2))
                .id(game.id)
                .transition(overlayTransition)
                .zIndex(2)
            }
        }
        .onPreferenceChange(SeleneBackdropRequestKey.self, perform: updateSharedBackdrop)
    }

    /// Layers with environment, sheets and lifecycle; split from `body` for the type checker.
    private var styled: some View {
        layers
        .allowsHitTesting(!nativeMenus.isTracking)
        .background(FullscreenCursorView())
        .background(StartupWindowView(fullscreen: settings.settings.startInFullscreen) {
            viewModel.isWindowSettling = false
        })
        .focusedSceneValue(\.nxMenuAvailability, nativeMenuAvailability)
        .overlay {
            SessionCardLayer(presenter: sessionCard, game: playedGame,
                             metadata: store.storeMetadata, artwork: artwork)
        }
        .background { launchCover }
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
        .environment(\.seleneSharesBackdrop, true)
        .environment(\.seleneShowButtonHints, settings.settings.showButtonHints)
        .environment(\.seleneButtonNames, settings.settings.buttonNames)
        .environmentObject(updater)
        .environmentObject(sources)
        .onAppear { [sources] in
            steamWatcher.onChange = { [weak sources] in sources?.steamFilesChanged() }
            sources.startIfEnabled()
        }
        .onReceive(sources.$libraryRoots) { roots in steamWatcher.watch(roots, root: sources.configuration.rootURL) }
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
            SteamPlaytimeCoordinator.shared.stop()
            SteamAchievementsStore.shared.stop()
            steamWatcher.stop()
            removeGestureKeyMonitor()
        }
        .onChange(of: viewModel.libraryGames) { _, games in
            runningGames.setGames(games)
        }
        .onChange(of: viewModel.catalogGames) { _, games in
            SteamPlayCoordinator.shared.setGames(games, sources: viewModel.catalogSourceConfigurations)
            SteamPlaytimeCoordinator.shared.setGames(games, sources: viewModel.catalogSourceConfigurations)
        }
        .onChange(of: viewModel.catalogSourceConfigurations) { _, sources in
            SteamPlayCoordinator.shared.setGames(viewModel.catalogGames, sources: sources)
            SteamPlaytimeCoordinator.shared.setGames(viewModel.catalogGames, sources: sources)
            SteamAchievementsStore.shared.setSources(sources)
        }
        .onReceive(playSessions.starts) { gameID in
            // A game that starts leads the Spotlight row, as on a console's home; a move in progress is left alone.
            guard viewModel.spotlight.lift == nil else { return }
            let order = SpotlightRow.playing(gameID, previousOrder: settings.settings.spotlightOrder)
            if order != settings.settings.spotlightOrder { settings.settings.spotlightOrder = order }
        }
        .onReceive(runningGames.$endedSession) { summary in
            sessionCard.ended(summary, enabled: settings.settings.showsSessionCard)
        }
        .onReceive(SteamPlayCoordinator.shared.$endedSession) { summary in
            sessionCard.ended(summary, enabled: settings.settings.showsSessionCard)
        }
        .onReceive(SteamPlayCoordinator.shared.$launchScreen) { screen in
            // A Steam game's launch screen is the nxnative one: shown on Play, leaving when the coordinator says.
            guard let screen else { return }
            if viewModel.launchOverlay?.game.id == screen.gameID {
                if screen.ready { viewModel.launchOverlay?.isReady = true }
            } else if !screen.ready, viewModel.launchOverlay == nil, let game = playedGame(screen.gameID) {
                viewModel.launchOverlay = LaunchOverlayState(game: game)
                SoundEffectService.shared.play(.launch)
            } else {
                // Not on screen (another launch is) or already over: there is no wait to hold the front for.
                SteamPlayCoordinator.shared.launchScreenClosed(screen.gameID)
            }
        }
        .onChange(of: viewModel.launchOverlay?.game.id) { _, shown in
            // The screen faded, the player dismissed it or another game's took its place: Arcane stops holding
            // the front for the Steam game.
            if let screen = SteamPlayCoordinator.shared.launchScreen, shown != screen.gameID {
                SteamPlayCoordinator.shared.launchScreenClosed(screen.gameID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            sessionCard.becameActive()
            SteamPlaytimeCoordinator.shared.refresh()
        }
        .onChange(of: settings.settings.showsSessionCard) { _, on in
            if !on { sessionCard.clear() }
        }
        .onChange(of: showsUpdateOffer) { viewModel.isUpdateOfferOpen = $1 }
        // Closing clears it once the fade has ended (`closeWelcome`), so nothing under it moves or takes input before.
        .onChange(of: showsWelcome) { if $1 { viewModel.isWelcomeOpen = true } }
        .onChange(of: router.route) { _, route in
            recordLastHome(route)
            switch route {
            case .addGame:
                viewModel.porting.addGameDidBecomeVisible(
                    defaults: settings.settings.gameDefaults,
                    returningFromBack: router.isReturningFromBack,
                    preservingSelection: setupSourceEntryID != nil
                )
            case .library, .collection, .detail:
                setupSourceEntryID = nil
                viewModel.porting.addGameDidLeave()
            default:
                break
            }
        }
    }

    var nativeGameCommands: some View {
        styled
        .environment(\.locale, localization.context.formatLocale)
        .environment(\.nxAppLocale, localization.context)
        .environment(\.catalogPersonalizations, viewModel.personalizations)
        .onChange(of: settings.settings.appLanguage) { updateLocale() }
        .onChange(of: settings.settings.appRegion) { updateLocale() }
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
}
