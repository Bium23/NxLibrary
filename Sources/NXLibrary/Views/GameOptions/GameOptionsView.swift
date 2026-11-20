import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

/// Selene's Game options: the current screen dimmed, then a centred column (1040u)
/// with the game's name and glass rows. Edit details opens its own list and a
/// removal asks in a Selene dialog. Rows, order and copy come from
/// `GameOptionsPresentation`; this view only draws them and runs the actions.
///
/// Input: Up/Down move (clamped), Left/Right change values, A activates, B (or Esc)
/// steps back: out of a dialog, then out of Edit details, then closes. Mouse: the
/// pointer alone never moves the focus; the wheel or trackpad scrolls the list
/// freely and, once it stops, the focus moves to the nearest row in view without
/// moving the list. A click activates.
/// What Game options reads from the game's files when it opens. The view holds it as a `@StateObject`, built once
/// per opening: the view's own initializer runs on every redraw of the shell and must not read files there.
final class GameOptionsFiles: ObservableObject {
    /// It parses the game's launcher file, which the rows must not do on every draw.
    let supportsRenderScale: Bool
    @Published var config: GameRuntimeConfig
    /// The build's settings and their values, for a build with saved choices; nil for an older build (`config`).
    @Published var snapshot: GameSettingsSnapshot?
    /// The Cheats row's value: read when Game options opens and when the panel closes, not on every draw. Nil (no chip)
    /// until the engine's answer is kept: the view's task asks for it off the main thread.
    @Published var cheatsValue: String?
    @Published var modsValue: String

    init(viewModel: AppViewModel, game: PortedGame) {
        supportsRenderScale = viewModel.runtimeSettings.supportsSetting("DM_RENDER_SCALE", for: game)
        config = viewModel.runtimeSettings.loadRuntimeConfig(for: game)
        snapshot = viewModel.runtimeSettings.settingsSnapshot(for: game)
        cheatsValue = viewModel.cheats.cheatRowValue(for: game)
        modsValue = viewModel.modsRowValue(for: game)
    }
}

struct GameOptionsView: View {
    @ObservedObject var viewModel: AppViewModel
    /// The Setup (`SetupModel`): the gate hint below Rebuild follows the engine in use.
    @ObservedObject var setup: SetupModel
    /// The Nintendo store's data (`StoreMetadataModel`): descriptions, screenshots and names shown here.
    @ObservedObject var store: StoreMetadataModel
    let game: PortedGame
    let origin: GameOptionsOrigin
    let onClose: () -> Void
    let onShowBuild: () -> Void
    let onMove: () -> Void
    @StateObject private var files: GameOptionsFiles
    private var supportsRenderScale: Bool { files.supportsRenderScale }
    var config: GameRuntimeConfig {
        get { files.config }
        nonmutating set { files.config = newValue }
    }
    var snapshot: GameSettingsSnapshot? {
        get { files.snapshot }
        nonmutating set { files.snapshot = newValue }
    }
    @State var level: GameOptionsLevel = .main
    /// The focused row by identity; nil means the top row of the level.
    @State var pickedRow: GameOptionsRow?
    @State var confirm: ConfirmTarget?
    /// Change artwork is open over the list; it takes the input until B closes it.
    @State var artworkOpen = false
    /// Change metadata, likewise.
    @State var metadataOpen = false
    /// The Cheats panel, likewise.
    @State var cheatsOpen = false
    @State var savesOpen = false
    /// The Mods panel, likewise.
    @State var modsOpen: Bool
    private var modsValue: String {
        get { files.modsValue }
        nonmutating set { files.modsValue = newValue }
    }
    @State var moreOpen = false
    var cheatsValue: String? {
        get { files.cheatsValue }
        nonmutating set { files.cheatsValue = newValue }
    }
    /// A panel over the list has the input.
    var panelOpen: Bool { artworkOpen || metadataOpen || cheatsOpen || modsOpen || savesOpen || moreOpen }
    @State var confirmFocus: SeleneConfirmButton = .cancel
    /// The row whose explanation is open beside its info button (a click on it, or Y on the focused row).
    @State var infoRow: GameOptionsRow?
    @State var keyMonitor: Any?
    /// Row frames in the list's viewport, written while scrolling without redrawing.
    @State var scrollBox = OptionsScrollBox()

    @Environment(\.seleneCanvas) var canvas
    @Environment(\.seleneReduceMotion) var reduceMotion

    enum ConfirmTarget: Equatable {
        case removeSources
        case removeGame
    }

    init(viewModel: AppViewModel, game: PortedGame, origin: GameOptionsOrigin,
         onClose: @escaping () -> Void, onShowBuild: @escaping () -> Void,
         onMove: @escaping () -> Void, opensMods: Bool = false) {
        self.viewModel = viewModel
        self.setup = viewModel.setup
        self.store = viewModel.store
        self.game = game
        self.origin = origin
        self.onClose = onClose
        self.onShowBuild = onShowBuild
        self.onMove = onMove
        // The autoclosure runs only when Game options opens, not on the shell's later redraws.
        _files = StateObject(wrappedValue: GameOptionsFiles(viewModel: viewModel, game: game))
        _modsOpen = State(initialValue: opensMods)
    }

    // MARK: - Model

    /// The game as the library holds it now: Attach sources, Favorite and Hidden change it while open.
    var current: PortedGame {
        viewModel.libraryGames.first { $0.id == game.id } ?? game
    }

    var presentation: GameOptionsPresentation {
        let game = current
        return GameOptionsPresentation(
            supportsRenderScale: supportsRenderScale,
            isPlayable: game.isPlayableLocally,
            sourcesDetached: !GameResourceState.sourcesAvailable(for: game),
            // Mirrors GameDetailView.toolchainBlocked: a known report that does not pass, without the override.
            toolchainBlocked: setup.isCheckingEnvironment || (setup.compatibilityReport != nil && !setup.canPassToolchainGate),
            toolchainHint: setup.isCheckingEnvironment ? L10n.text("Checking environment") : setup.toolchainGateSummary?.buildHint,
            hasStorePage: store.storeMetadata[game.id]?.storeURL != nil,
            offersStoreSearch: (store.storeMetadata[game.id]?.description ?? "").isEmpty
                && store.nintendoStoreSearchURL(for: game) != nil,
            gameName: game.name,
            appPath: game.url.path,
            canDeleteBundle: game.canDeleteAppBundle(),
            cheatsValue: cheatsValue ?? "",
            modsValue: modsValue,
            settings: snapshot
        )
    }

    var rows: [GameOptionsRow] {
        presentation.focusableRows(level: level, origin: origin)
    }

    /// The focused row, re-resolved against the rows of this draw so that rows
    /// appearing above it (a Store page arriving late) do not move the focus.
    var focusedRow: GameOptionsRow? {
        let rows = self.rows
        return GameOptionsFocus(row: pickedRow, in: rows).row(in: rows)
    }

    // MARK: - Body

    var body: some View {
        let p = presentation
        return ZStack {
            // A light shade: the screen behind is blurred (AppShellView), so the options read without darkening it much.
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { back() }

            VStack(spacing: 0) {
                column(p)
                // Where the screen underneath had its hints (which hide while this is open).
                SeleneHintsBar(left: [HintItem(.b, L10n.text("Back"))], right: rightHints(p),
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A panel (Change artwork, Change metadata, Cheats) takes the screen; the list never shows through.
            .opacity(panelOpen ? 0 : 1)
            .allowsHitTesting(!panelOpen)

            if artworkOpen {
                ChangeArtworkView(viewModel: viewModel, subject: PersonalizationSubject(current, viewModel: viewModel)) { artworkOpen = false }
                    .transition(.opacity)
                    .zIndex(2)
            }

            if metadataOpen {
                ChangeMetadataView(viewModel: viewModel, subject: PersonalizationSubject(current, viewModel: viewModel)) { metadataOpen = false }
                    .transition(.opacity)
                    .zIndex(2)
            }

            if cheatsOpen {
                CheatsPanel(viewModel: viewModel, game: current, onRebuild: {
                    cheatsOpen = false
                    rebuild(current)
                }, onClose: {
                    cheatsOpen = false
                    cheatsValue = viewModel.cheats.cheatRowValue(for: current)
                })
                .transition(.opacity)
                .zIndex(2)
            }

            if modsOpen {
                ModsPanel(viewModel: viewModel, game: current) {
                    modsOpen = false
                    modsValue = viewModel.modsRowValue(for: current)
                }
                .transition(.opacity)
                .zIndex(2)
            }

            if savesOpen {
                SavesPanel(viewModel: viewModel, game: current) { savesOpen = false }
                    .transition(.opacity)
                    .zIndex(2)
            }

            if moreOpen {
                MoreSettingsPanel(viewModel: viewModel, game: current) {
                    moreOpen = false
                    snapshot = viewModel.runtimeSettings.settingsSnapshot(for: current)
                }
                .transition(.opacity)
                .zIndex(2)
            }

            if let target = confirm {
                confirmOverlay(target)
                    .transition(reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: confirm)
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: panelOpen)
        .onAppear {
            installKeyMonitor()
            setup.prepareBuildEnvironmentIfNeeded()
        }
        .onDisappear(perform: removeKeyMonitor)
        .task {
            guard cheatsValue == nil else { return }
            await viewModel.cheats.prepare(for: current)
            cheatsValue = viewModel.cheats.cheatRowValue(for: current)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxGameOptionsGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
        .onChange(of: config) { _, newValue in
            viewModel.runtimeSettings.saveRuntimeConfig(newValue, for: game)
        }
    }

}

/// Scroll bookkeeping for Game options. A reference type, so writing it on every
/// scroll frame does not redraw the panel.
final class OptionsScrollBox {
    static let space = "gameOptionsList"
    /// Row frames in the list's content, top-down.
    var frames: [GameOptionsRow: CGRect] = [:]
    weak var window: NSWindow?
    var pointer: CGPoint = .zero
    var settle: DispatchWorkItem?
    /// The next focus change came from the wheel: do not scroll to it.
    var holdScroll = false

    /// The clip view of the scroll view under the pointer of the last scroll event.
    func clipView() -> NSClipView? {
        guard let content = window?.contentView else { return nil }
        var view = content.hitTest(content.convert(pointer, from: nil))
        while let current = view {
            if let scroll = current as? NSScrollView { return scroll.contentView }
            view = current.superview
        }
        return nil
    }
}

struct OptionRowFrames: PreferenceKey {
    static var defaultValue: [GameOptionsRow: CGRect] = [:]
    static func reduce(value: inout [GameOptionsRow: CGRect], nextValue: () -> [GameOptionsRow: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
