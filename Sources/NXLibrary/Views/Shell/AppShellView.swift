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

    public init() {}

    public var body: some View {
        ZStack {
            SeleneTheme.canvas.ignoresSafeArea()
            content
            if router.isMenuPresented {
                MenuOverlayView(router: router) { action in
                    handleMenu(action)
                }
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1100, minHeight: 700)
        .sheet(isPresented: $viewModel.showSetupSheet) {
            SetupView(viewModel: viewModel)
        }
        .sheet(item: $viewModel.gameForSettingsSheet) { game in
            GameSettingsSheetView(viewModel: viewModel, game: game)
        }
        .onAppear(perform: startRuntime)
        .onDisappear { processObserver?.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryPlayFocused)) { _ in
            guard router.route == .library, let game = viewModel.currentFocusedGame else { return }
            viewModel.launchGame(game)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryCheckUpstream)) { _ in
            viewModel.checkUpstreamChangelog()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenMenu)) { _ in
            router.isMenuPresented = true
        }
        .onExitCommand {
            if router.isMenuPresented {
                router.closeMenu()
            } else if router.route == .library {
                router.isMenuPresented = true
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
            LibraryRootView(
                viewModel: viewModel,
                router: router,
                settings: settings,
                playSessions: playSessions,
                artwork: artwork
            )
        case .detail:
            LibraryView(viewModel: viewModel)
                .padding(.top, 28)
        case .settings:
            SystemView(viewModel: viewModel)
                .padding(.top, 28)
        case .addGame:
            BuildView(viewModel: viewModel)
                .padding(.top, 28)
        case .console:
            LogsView(viewModel: viewModel)
                .padding(.top, 28)
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
            switch router.route {
            case .library:
                viewModel.handleLibraryGamepadAction(action)
            default:
                if action == .menu {
                    router.isMenuPresented = true
                } else if action == .cancel {
                    router.back()
                }
            }
        }
    }

    private func handleMenu(_ action: MenuAction) {
        router.closeMenu()
        switch action {
        case .library:
            router.showLibrary()
        case .addGame:
            router.openAddGame()
        case .settings:
            router.openSettings(.general)
        case .console:
            router.openConsole()
        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }
}
