import SwiftUI
import AppKit
import NXLibraryCore

public struct AppShellView: View {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var router = AppRouter()
    @StateObject private var settings = AppSettingsStore()
    @StateObject private var playSessions = PlaySessionStore()
    @StateObject private var artwork = ArtworkStore()
    @State private var processObserver: GameProcessObserver?
    @State private var gestureKeyMonitor: Any?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    public init() {}

    /// Spotlight or Collection: the screens that pick a game.
    private var isHomeRoute: Bool {
        router.route == .library || router.route == .collection
    }

    private var reduceMotion: Bool {
        settings.settings.reduceMotion || accessibilityReduceMotion
    }

    public var body: some View {
        ZStack {
            SeleneTheme.scrim.ignoresSafeArea()
            content
            if router.isMenuPresented {
                MenuOverlayView(router: router) { action in
                    handleMenu(action)
                }
                .transition(.opacity)
                .zIndex(1)
            }
            if let game = viewModel.gameForSettingsSheet {
                GameOptionsView(
                    viewModel: viewModel,
                    game: game,
                    onClose: { viewModel.gameForSettingsSheet = nil },
                    onShowBuild: {
                        viewModel.gameForSettingsSheet = nil
                        router.openAddGame()
                    }
                )
                .transition(reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(2)
            }
        }
        .seleneCanvasRoot()
        .animation(reduceMotion ? nil : SeleneTheme.screen,
                   value: viewModel.gameForSettingsSheet?.id)
        .animation(reduceMotion ? nil : SeleneTheme.quick,
                   value: router.isMenuPresented)
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
            processObserver?.stop()
            removeGestureKeyMonitor()
        }
        .onChange(of: router.route) { route in
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
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryPlayFocused)) { _ in
            guard isHomeRoute,
                  let game = viewModel.currentFocusedGame else { return }
            viewModel.launchGame(game)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenDetails)) { _ in
            guard !router.isMenuPresented,
                  viewModel.gameForSettingsSheet == nil,
                  isHomeRoute,
                  let game = viewModel.currentFocusedGame else { return }
            router.showDetail(game.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenGameOptions)) { _ in
            guard !router.isMenuPresented else { return }
            switch router.route {
            case .library, .collection:
                if let game = viewModel.currentFocusedGame {
                    viewModel.gameForSettingsSheet = game
                }
            case .detail(let id):
                if let game = viewModel.libraryGames.first(where: { $0.id == id }) {
                    viewModel.gameForSettingsSheet = game
                }
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryCheckUpstream)) { _ in
            viewModel.checkUpstreamChangelog()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenMenu)) { _ in
            guard viewModel.gameForSettingsSheet == nil else { return }
            router.isMenuPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenSettings)) { _ in
            router.closeMenu()
            router.openSettings(.general)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenConsole)) { _ in
            router.closeMenu()
            router.openConsole()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenLibrary)) { _ in
            router.closeMenu()
            router.showLibrary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenAddGame)) { _ in
            router.closeMenu()
            openFreshAddGame()
        }
        .onExitCommand {
            if viewModel.gameForSettingsSheet != nil {
                viewModel.gameForSettingsSheet = nil
            } else if router.isMenuPresented {
                router.closeMenu()
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
                artwork: artwork
            )
        case .collection:
            // Until Collection is rebuilt (Task 13) it is the previous library screen.
            LibraryRootView(
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
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        playSessions.reconcile(runningBundleIDs: running)
        artwork.trimCache()
        let observer = GameProcessObserver(store: playSessions)
        observer.start()
        processObserver = observer
        viewModel.router = router
        installGestureKeyMonitor()
        GameControllerService.shared.onAction = { [weak viewModel, weak router] action in
            guard let viewModel, let router else { return }
            if router.isMenuPresented {
                switch action {
                case .navigateLeft:
                    router.moveMenu(by: -1)
                case .navigateRight:
                    router.moveMenu(by: 1)
                case .confirm:
                    router.closeMenu()
                    switch router.menuSelection.selected {
                    case .library: router.showLibrary()
                    case .addGame: router.openAddGame()
                    case .settings: router.openSettings(.general)
                    case .console: router.openConsole()
                    case .quit: NSApplication.shared.terminate(nil)
                    }
                case .cancel:
                    router.closeMenu()
                default:
                    break
                }
                return
            }
            if viewModel.gameForSettingsSheet != nil {
                NotificationCenter.default.post(name: .nxGameOptionsGamepadAction, object: action)
                return
            }
            switch router.route {
            case .library:
                NotificationCenter.default.post(name: .nxSpotlightGamepadAction, object: action)
            case .collection:
                if action == .view {
                    router.showLibrary()
                } else {
                    viewModel.handleLibraryGamepadAction(action)
                }
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

    /// App-level monitor for the keyboard equivalents of the controller gestures.
    /// Handles only Tab, Cmd+F, Cmd+, , Home and End; every other event passes through.
    private func installGestureKeyMonitor() {
        guard gestureKeyMonitor == nil else { return }
        gestureKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [router] event in
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let typing = event.window?.firstResponder is NSText
            var action: GamepadAction?
            var consume = true
            switch (event.keyCode, key, mods) {
            case (48, _, []):                       // Tab
                if typing { return event }
                action = .view
            case (_, "f", [.command]):              // Cmd+F
                // Collection (the old library) still binds Cmd+F to its search button; Find a game replaces it later.
                if typing || router.route == .collection { return event }
                action = .viewHold
            case (_, ",", [.command]):              // Cmd+,
                // Keep the Settings menu shortcut working: dispatch but do not consume.
                action = .menuHold
                consume = false
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
            return consume ? nil : event
        }
    }

    private func removeGestureKeyMonitor() {
        if let monitor = gestureKeyMonitor { NSEvent.removeMonitor(monitor) }
        gestureKeyMonitor = nil
    }

    private func handleMenu(_ action: MenuAction) {
        router.closeMenu()
        switch action {
        case .library:
            router.showLibrary()
        case .addGame:
            openFreshAddGame()
        case .settings:
            router.openSettings(.general)
        case .console:
            router.openConsole()
        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }

    private func openFreshAddGame() {
        if router.route == .addGame, !viewModel.isBuilding {
            viewModel.startNewAddGame(defaults: settings.settings.gameDefaults)
        } else {
            router.openAddGame()
        }
    }
}
