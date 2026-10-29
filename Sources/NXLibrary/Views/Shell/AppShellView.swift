import SwiftUI
import AppKit
import Combine
import NXLibraryCore

public struct AppShellView: View {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var router = AppShellView.startingRouter()
    @StateObject private var settings = AppSettingsStore()
    @StateObject private var playSessions = PlaySessionStore()
    @StateObject private var artwork = ArtworkStore()
    @StateObject private var runningGames = RunningGameMonitor()
    @State private var gestureKeyMonitor: Any?
    /// Dismisses the Close Game confirmation when its game quits by itself.
    @State private var closeGameWatch: AnyCancellable?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    public init() {}

    /// The router, already on the screen the Start on setting names.
    private static func startingRouter() -> AppRouter {
        let saved = AppSettingsStore().settings
        let router = AppRouter()
        router.setInitialRoute(AppRouter.initialRoute(for: saved.startOn, last: saved.lastHome))
        return router
    }

    /// Spotlight or Collection: the screens that pick a game.
    private var isHomeRoute: Bool {
        router.route == .library || router.route == .collection
    }

    /// The Close Game confirmation is open; menu commands and the dialog's input wait for it.
    private var isCloseGameOpen: Bool { viewModel.gameToClose != nil }

    private var reduceMotion: Bool {
        settings.settings.reduceMotion || accessibilityReduceMotion
    }

    /// The launch screen sits over everything, menu included, until the game's window shows.
    @ViewBuilder private var launchLayer: some View {
        if let state = viewModel.launchOverlay {
            LaunchScreenView(state: state, viewModel: viewModel, artwork: artwork,
                             settings: settings.settings, reduceMotion: reduceMotion)
                .id(state.game.id)
        }
    }

    /// The screen plus the overlays that sit on it; split from `body` for the type checker.
    private var layers: some View {
        ZStack {
            SeleneTheme.scrim.ignoresSafeArea()
            content
            if let game = viewModel.gameToClose {
                closeGameOverlay(game)
                    .transition(.opacity)
                    .zIndex(3)
            }
            if router.isMenuPresented {
                MenuOverlayView(
                    router: router,
                    onSelect: { runMenuAction($0) },
                    onSelectPower: { runPower($0) }
                )
                .transition(.opacity)
                .zIndex(1)
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
                    }
                )
                .transition(reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(2)
            }
        }
    }

    /// Layers with environment, sheets and lifecycle; split from `body` for the type checker.
    private var styled: some View {
        layers
        .overlay { launchLayer }
        .modifier(SoundCueHooks(router: router, viewModel: viewModel))
        .seleneCanvasRoot()
        .animation(reduceMotion ? nil : SeleneTheme.screen,
                   value: viewModel.gameForSettingsSheet?.id)
        .animation(reduceMotion ? nil : SeleneTheme.quick,
                   value: router.isMenuPresented)
        .animation(reduceMotion ? nil : SeleneTheme.quick,
                   value: viewModel.gameToClose?.id)
        .environment(\.seleneReduceMotion, reduceMotion)
        .environment(\.seleneShowButtonHints, settings.settings.showButtonHints)
        .environment(\.seleneButtonNames, settings.settings.buttonNames)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1100, minHeight: 700)
        .sheet(isPresented: $viewModel.showSetupSheet) {
            SetupView(viewModel: viewModel)
        }
        .onAppear(perform: startRuntime)
        .onDisappear {
            runningGames.stop()
            removeGestureKeyMonitor()
        }
        .onChange(of: viewModel.libraryGames) { games in
            runningGames.setGames(games)
        }
        .onChange(of: router.route) { route in
            recordLastHome(route)
            switch route {
            case .addGame:
                viewModel.addGameDidBecomeVisible(
                    defaults: settings.settings.gameDefaults,
                    returningFromBack: router.isReturningFromBack
                )
            case .library, .collection, .detail:
                viewModel.addGameDidLeave()
            default:
                break
            }
        }
    }

    public var body: some View {
        styled
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryPlayFocused)) { _ in
            guard !router.isMenuPresented,
                  isHomeRoute,
                  viewModel.gameForSettingsSheet == nil,
                  !isCloseGameOpen,
                  let game = viewModel.currentFocusedGame else { return }
            viewModel.launchGame(game)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenDetails)) { _ in
            guard !router.isMenuPresented,
                  viewModel.gameForSettingsSheet == nil,
                  !isCloseGameOpen,
                  isHomeRoute,
                  let game = viewModel.currentFocusedGame else { return }
            router.showDetail(game.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenGameOptions)) { _ in
            guard !router.isMenuPresented else { return }
            switch router.route {
            case .library:
                if let game = viewModel.currentFocusedGame {
                    viewModel.openGameOptions(game, from: .spotlight)
                }
            case .collection:
                if let game = viewModel.currentFocusedGame {
                    viewModel.openGameOptions(game, from: .collection)
                }
            case .detail(let id):
                if let game = viewModel.libraryGames.first(where: { $0.id == id }) {
                    viewModel.openGameOptions(game, from: .details)
                }
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryCheckUpstream)) { _ in
            guard !router.isMenuPresented, !router.isScreenshotViewerOpen else { return }
            viewModel.checkUpstreamChangelog()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenMenu)) { _ in
            guard viewModel.gameForSettingsSheet == nil, !router.isScreenshotViewerOpen else { return }
            router.isMenuPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenSettings)) { _ in
            guard !router.isScreenshotViewerOpen, viewModel.gameForSettingsSheet == nil else { return }
            router.closeMenu()
            router.openSettings(.startUp)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenConsole)) { _ in
            guard !router.isScreenshotViewerOpen, viewModel.gameForSettingsSheet == nil else { return }
            router.closeMenu()
            router.openConsole()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenLibrary)) { _ in
            guard !router.isScreenshotViewerOpen, viewModel.gameForSettingsSheet == nil else { return }
            router.closeMenu()
            router.showLibrary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenAddGame)) { _ in
            guard !router.isMenuPresented, !router.isScreenshotViewerOpen,
                  viewModel.gameForSettingsSheet == nil else { return }
            router.closeMenu()
            openFreshAddGame()
        }
        .onExitCommand {
            if router.isScreenshotViewerOpen {
                // The viewer's key monitor closes it.
            } else if viewModel.gameToClose != nil {
                viewModel.dismissCloseGame()
            } else if viewModel.gameForSettingsSheet != nil {
                // Game options steps back (dialog, then Edit details) or closes.
                NotificationCenter.default.post(name: .nxGameOptionsGamepadAction, object: GamepadAction.cancel)
            } else if router.isMenuPresented {
                menuInput(.cancel)
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
        .alert("NX Library", isPresented: Binding(
            get: { viewModel.alertMessage != nil },
            set: { if !$0 { viewModel.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.alertMessage = nil }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch router.route {
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
            AddGameView(viewModel: viewModel,
                        router: router,
                        showsHints: settings.settings.showButtonHints)
        case .console:
            ConsoleView(viewModel: viewModel, router: router)
        }
    }

    private func startRuntime() {
        viewModel.playSessionStore = playSessions
        viewModel.settingsStore = settings
        SoundEffectService.shared.bind(to: settings)
        artwork.trimCache()
        runningGames.start(sessions: playSessions)
        runningGames.setGames(viewModel.libraryGames)
        closeGameWatch = runningGames.$runningGameIDs.sink { [weak viewModel] ids in
            // The game under Close Game quit by itself: its confirmation has nothing left to close.
            guard let viewModel, let game = viewModel.gameToClose, !ids.contains(game.id) else { return }
            viewModel.dismissCloseGame()
        }
        viewModel.router = router
        installGestureKeyMonitor()
        GameControllerService.shared.onAction = { [weak viewModel, weak router] action in
            guard let viewModel, let router else { return }
            if viewModel.gameToClose != nil {
                closeGameInput(action)
                return
            }
            if router.isMenuPresented {
                menuInput(action)
                return
            }
            if viewModel.gameForSettingsSheet != nil {
                NotificationCenter.default.post(name: .nxGameOptionsGamepadAction, object: action)
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

    // MARK: - Close Game confirmation

    private func closeGameOverlay(_ game: PortedGame) -> some View {
        ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { viewModel.dismissCloseGame() }
            SeleneConfirmDialog(title: "Close \(game.name)?",
                                message: "Unsaved progress in the game will be lost.",
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
            // The screenshot viewer owns the keyboard (its own monitor handles it); no navigating underneath.
            if router.isScreenshotViewerOpen { return event }
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            // The Close Game confirmation takes the keyboard: arrows, Return, Space and Esc go to it.
            if viewModel.gameToClose != nil, mods.isEmpty {
                let closeAction: GamepadAction?
                switch event.keyCode {
                case 123: closeAction = .navigateLeft
                case 124: closeAction = .navigateRight
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
            if router.isMenuPresented, mods.isEmpty {
                let menuAction: GamepadAction?
                switch event.keyCode {
                case 123: menuAction = .navigateLeft     // Left arrow
                case 124: menuAction = .navigateRight    // Right arrow
                case 125: menuAction = .navigateDown     // Down arrow
                case 126: menuAction = .navigateUp       // Up arrow
                case 36, 76, 49: menuAction = .confirm   // Return, keypad Enter, Space
                case 53: menuAction = .cancel            // Esc
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

    /// A row button. The menu closes before it navigates; Power only opens or closes its pills.
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
        case .settings:
            router.closeMenu()
            router.openSettings(.startUp)
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
            viewModel.alertMessage = "NX Library could not restart: \(error.localizedDescription)"
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
            .onChange(of: router.isMenuPresented) { open in
                SoundEffectService.shared.play(open ? .openPanel : .back)
            }
            .onChange(of: viewModel.gameForSettingsSheet?.id) { id in
                SoundEffectService.shared.play(id == nil ? .back : .openPanel)
            }
            .onChange(of: viewModel.gameToClose?.id) { id in
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
