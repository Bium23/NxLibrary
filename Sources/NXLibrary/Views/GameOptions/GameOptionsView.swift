import SwiftUI
import AppKit
import NXLibraryCore

/// Selene's Game options: the current screen dimmed, then a centred column (864u)
/// with the game's name and glass rows. Edit details opens its own list and a
/// removal asks in a Selene dialog. Rows, order and copy come from
/// `GameOptionsPresentation`; this view only draws them and runs the actions.
///
/// Input: Up/Down move (clamped), Left/Right change values, A activates, B (or Esc,
/// which the shell forwards) steps back: out of a dialog, then out of Edit details,
/// then closes. Mouse: hover focuses, click activates.
struct GameOptionsView: View {
    @ObservedObject var viewModel: AppViewModel
    let game: PortedGame
    let origin: GameOptionsOrigin
    let onClose: () -> Void
    let onShowBuild: () -> Void
    let onMove: () -> Void
    /// Read once: it parses the game's launcher file, which the rows must not do on every draw.
    private let supportsRenderScale: Bool

    @State private var config: GameRuntimeConfig
    @State private var level: GameOptionsLevel = .main
    @State private var mainFocus = GameOptionsFocus()
    @State private var detailsFocus = GameOptionsFocus()
    @State private var confirm: ConfirmTarget?
    @State private var confirmFocus: SeleneConfirmButton = .cancel

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    enum ConfirmTarget: Equatable {
        case removeSources
        case removeGame
    }

    init(viewModel: AppViewModel, game: PortedGame, origin: GameOptionsOrigin,
         onClose: @escaping () -> Void, onShowBuild: @escaping () -> Void,
         onMove: @escaping () -> Void) {
        self.viewModel = viewModel
        self.game = game
        self.origin = origin
        self.onClose = onClose
        self.onShowBuild = onShowBuild
        self.onMove = onMove
        supportsRenderScale = viewModel.supportsSetting("DM_RENDER_SCALE", for: game)
        _config = State(initialValue: viewModel.loadRuntimeConfig(for: game))
    }

    // MARK: - Model

    /// The game as the library holds it now: Attach sources, Favorite and Hidden change it while open.
    private var current: PortedGame {
        viewModel.libraryGames.first { $0.id == game.id } ?? game
    }

    private var presentation: GameOptionsPresentation {
        let game = current
        return GameOptionsPresentation(
            supportsRenderScale: supportsRenderScale,
            isPlayable: game.isPlayableLocally,
            sourcesDetached: !game.sources.contains { $0.type == .base },
            // Mirrors GameDetailView.toolchainBlocked: a known report that does not pass, without the override.
            toolchainBlocked: viewModel.compatibilityReport != nil && !viewModel.canPassToolchainGate,
            hasStorePage: viewModel.storeMetadata[game.id]?.storeURL != nil,
            gameName: game.name,
            appPath: game.url.path,
            canDeleteBundle: game.canDeleteAppBundle()
        )
    }

    private var rows: [GameOptionsRow] {
        presentation.focusableRows(level: level, origin: origin)
    }

    private var focusedRow: GameOptionsRow? {
        (level == .main ? mainFocus : detailsFocus).row(in: rows)
    }

    // MARK: - Body

    var body: some View {
        let p = presentation
        return ZStack {
            SeleneTheme.scrim65
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                column(p)
                SeleneHintsBar(left: [HintItem(.b, "Back")], right: [HintItem(.a, "Select")])
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let target = confirm {
                confirmOverlay(target)
                    .transition(reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: confirm)
        .onMoveCommand(perform: handleMove)
        .seleneActivationKeys(activateFocused)
        .onReceive(NotificationCenter.default.publisher(for: .nxGameOptionsGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
        .onChange(of: config) { newValue in
            viewModel.saveRuntimeConfig(newValue, for: game)
        }
    }

    private func column(_ p: GameOptionsPresentation) -> some View {
        let entries = p.entries(level: level, origin: origin)
        let focused = focusedRow
        return VStack(alignment: .leading, spacing: 0) {
            Text("GAME OPTIONS")
                .seleneFont(15, .semibold)
                .foregroundColor(SeleneTheme.ink60)
                .padding(.leading, canvas.u(8))
            Text(current.name)
                .seleneFont(40)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(1)
                .padding(.leading, canvas.u(6))
                .padding(.bottom, canvas.u(20))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: canvas.u(8)) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            entryView(entry, p, focused: focused)
                        }
                    }
                    .padding(.bottom, canvas.u(24))
                }
                .scrollIndicators(.hidden)
                .onChange(of: focusedRow) { row in
                    guard let row else { return }
                    withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                        proxy.scrollTo(row.rawValue, anchor: .center)
                    }
                }
            }
            .id(level)
        }
        .frame(width: canvas.u(864), alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, canvas.u(84))
    }

    @ViewBuilder
    private func entryView(_ entry: GameOptionsEntry, _ p: GameOptionsPresentation,
                           focused: GameOptionsRow?) -> some View {
        switch entry {
        case .row(let row):
            rowView(row, p, focused: focused)
        case .heading(let text):
            Text(text)
                .seleneFont(17, .semibold)
                .foregroundColor(SeleneTheme.glyph)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, canvas.u(26))
                .padding(.top, canvas.u(16))
        case .note(let title, let text):
            VStack(alignment: .leading, spacing: canvas.u(3)) {
                Text(title)
                    .seleneFont(21, .medium)
                    .foregroundColor(SeleneTheme.ink60)
                Text(text)
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, canvas.u(26))
            .padding(.top, canvas.u(18))
            .padding(.trailing, canvas.u(24))
            .padding(.bottom, canvas.u(18))
            .background(RoundedRectangle(cornerRadius: canvas.u(16), style: .continuous)
                .fill(SeleneTheme.glass))
        case .gap:
            // Eight units of stack spacing make the 24u gap before a danger zone.
            Color.clear.frame(height: canvas.u(16))
        }
    }

    private func rowView(_ row: GameOptionsRow, _ p: GameOptionsPresentation,
                         focused: GameOptionsRow?) -> some View {
        SeleneOptionRow(icon: row.icon,
                        title: row.title,
                        about: p.about(row),
                        focused: focused == row,
                        destructive: row.isDestructive,
                        enabled: !p.isDimmed(row)) {
            trailing(row)
        }
        .help(p.info(row) ?? "")
        .contentShape(Rectangle())
        .onTapGesture { activate(row) }
        .onHover { hovering in
            if hovering { setFocus(row) }
        }
        .id(row.rawValue)
    }

    @ViewBuilder
    private func trailing(_ row: GameOptionsRow) -> some View {
        if row.isToggle {
            // The row takes the click; the switch only shows the state.
            SeleneSwitch(isOn: .constant(toggleValue(row))).allowsHitTesting(false)
        } else if row.isChoice {
            SeleneValueChip(text: choiceText(row))
        } else if row.opensSubmenu {
            MaterialIconView(.chevron, size: 24)
                .foregroundColor(SeleneTheme.ink60)
        } else {
            EmptyView()
        }
    }

    private func toggleValue(_ row: GameOptionsRow) -> Bool {
        switch row {
        case .favorite: return current.isFavorite
        case .hidden: return current.isHidden
        case .fullscreen: return config.fullscreen
        case .fps60: return config.enable60FPS
        case .metalFX: return config.enableMetalFXUpscale
        case .metalHUD: return config.enableMetalHUD
        case .rumble: return config.rumble
        default: return false
        }
    }

    private func choiceText(_ row: GameOptionsRow) -> String {
        switch row {
        case .consoleMode:
            return GameOptionsValues.consoleModeLabel(docked: config.isDockedMode)
        case .language:
            return viewModel.availableLanguages.first { $0.code == config.language }?.label ?? config.language
        case .rumbleStrength:
            return "\(config.rumbleGain)"
        case .renderScale:
            return GameOptionsValues.renderScaleLabel(config.renderScale)
        default:
            return ""
        }
    }

    // MARK: - Confirmation

    private func confirmOverlay(_ target: ConfirmTarget) -> some View {
        let copy = confirmCopy(target)
        return ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissConfirm() }
            SeleneConfirmDialog(title: copy.title,
                                message: copy.message,
                                confirmTitle: copy.confirm,
                                focus: $confirmFocus,
                                onCancel: dismissConfirm,
                                onConfirm: runConfirm)
        }
    }

    private func confirmCopy(_ target: ConfirmTarget) -> (title: String, message: String, confirm: String) {
        switch target {
        case .removeGame:
            let copy = presentation.removal
            return (copy.title, copy.message, copy.confirmTitle)
        case .removeSources:
            let info = presentation.info(.removeSources) ?? ""
            return ("Remove sources and build cache?",
                    info + "\n\n" + viewModel.sourceRemovalSummary(for: current),
                    "Remove")
        }
    }

    private func askConfirm(_ target: ConfirmTarget) {
        confirmFocus = .cancel
        confirm = target
    }

    private func dismissConfirm() {
        guard confirm != nil else { return }
        confirm = nil
        confirmFocus = .cancel
    }

    private func runConfirm() {
        guard let target = confirm else { return }
        confirm = nil
        confirmFocus = .cancel
        SoundEffectService.shared.play(.click)
        switch target {
        case .removeSources:
            viewModel.removeSources(for: current)
            onClose()
        case .removeGame:
            viewModel.deletePortedGame(current)
            onClose()
        }
    }

    // MARK: - Focus

    private func setFocus(_ row: GameOptionsRow) {
        if level == .main {
            mainFocus.focus(row, in: rows)
        } else {
            detailsFocus.focus(row, in: rows)
        }
    }

    private func moveFocus(by delta: Int) {
        let previous = focusedRow
        if level == .main {
            mainFocus.move(by: delta, count: rows.count)
        } else {
            detailsFocus.move(by: delta, count: rows.count)
        }
        if focusedRow != previous {
            SoundEffectService.shared.play(.focus)
        }
    }

    private func enterEditDetails() {
        level = .editDetails
        detailsFocus = GameOptionsFocus()
        // The store link needs the store metadata; Details asks for it the same way.
        viewModel.loadStoreMetadata(for: current)
    }

    private func leaveEditDetails() {
        level = .main
        SoundEffectService.shared.play(.focus)
    }

    // MARK: - Input

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .up: navigate(by: -1)
        case .down: navigate(by: 1)
        case .left: horizontal(by: -1)
        case .right: horizontal(by: 1)
        default: break
        }
    }

    private func handleGamepad(_ action: GamepadAction) {
        switch action {
        case .navigateUp: navigate(by: -1)
        case .navigateDown: navigate(by: 1)
        case .navigateLeft: horizontal(by: -1)
        case .navigateRight: horizontal(by: 1)
        case .confirm: activateFocused()
        case .cancel: back()
        case .secondaryAction, .menu:
            if confirm != nil { dismissConfirm() } else { onClose() }
        default: break
        }
    }

    private func navigate(by delta: Int) {
        guard confirm == nil else { return }
        moveFocus(by: delta)
    }

    /// Left/Right: the dialog's pills, or the value of a focused choice row.
    private func horizontal(by delta: Int) {
        if confirm != nil {
            let next: SeleneConfirmButton = delta < 0 ? .cancel : .confirm
            if next != confirmFocus {
                confirmFocus = next
                SoundEffectService.shared.play(.focus)
            }
            return
        }
        guard let row = focusedRow, row.isChoice else { return }
        adjust(row, by: delta)
    }

    /// B: leave the dialog, then Edit details, then close.
    private func back() {
        if confirm != nil {
            dismissConfirm()
        } else if level == .editDetails {
            leaveEditDetails()
        } else {
            onClose()
        }
    }

    /// A on the focused row (also Return and Space).
    private func activateFocused() {
        if confirm != nil {
            if confirmFocus == .confirm { runConfirm() } else { dismissConfirm() }
            return
        }
        guard let row = focusedRow else { return }
        perform(row)
    }

    private func activate(_ row: GameOptionsRow) {
        guard confirm == nil else { return }
        setFocus(row)
        perform(row)
    }

    /// Left/Right on a choice row: step backwards or forwards.
    private func adjust(_ row: GameOptionsRow, by delta: Int) {
        SoundEffectService.shared.play(.click)
        switch row {
        case .consoleMode:
            config.isDockedMode.toggle()
        case .language:
            cycleLanguage(by: delta)
        case .rumbleStrength:
            config.rumbleGain = GameOptionsValues.steppedRumbleStrength(config.rumbleGain, by: delta)
        case .renderScale:
            config.renderScale = GameOptionsValues.steppedRenderScale(config.renderScale, by: delta)
        default:
            break
        }
    }

    private func cycleLanguage(by delta: Int) {
        let options = viewModel.availableLanguages
        guard !options.isEmpty else { return }
        let index = options.firstIndex { $0.code == config.language }
        let next = GameOptionsValues.steppedIndex(index, by: delta, count: options.count)
        config.language = options[next].code
    }

    /// The row's action. A on a choice row steps it forwards.
    private func perform(_ row: GameOptionsRow) {
        switch row {
        case .play:
            guard presentation.canPlay else {
                SoundEffectService.shared.play(.error)
                return
            }
            SoundEffectService.shared.play(.click)
            onClose()
            viewModel.launchGame(current)
        case .move:
            SoundEffectService.shared.play(.click)
            onMove()
        case .favorite:
            SoundEffectService.shared.play(.click)
            viewModel.toggleFavorite(current)
        case .hidden:
            SoundEffectService.shared.play(.click)
            let hiding = !current.isHidden
            viewModel.toggleHidden(current)
            // Hidden games leave the lists; the options go with them.
            if hiding { onClose() }
        case .fullscreen:
            SoundEffectService.shared.play(.click)
            config.fullscreen.toggle()
        case .fps60:
            SoundEffectService.shared.play(.click)
            config.enable60FPS.toggle()
        case .metalFX:
            SoundEffectService.shared.play(.click)
            config.enableMetalFXUpscale.toggle()
        case .metalHUD:
            SoundEffectService.shared.play(.click)
            config.enableMetalHUD.toggle()
        case .consoleMode, .language, .rumbleStrength, .renderScale:
            adjust(row, by: 1)
        case .rumble:
            SoundEffectService.shared.play(.click)
            config.rumble.toggle()
        case .restoreDefaults:
            SoundEffectService.shared.play(.click)
            config = GameRuntimeConfig()
        case .rebuild:
            rebuild(current)
        case .showInFinder:
            SoundEffectService.shared.play(.click)
            viewModel.revealInFinder(url: current.url)
        case .openSaves:
            SoundEffectService.shared.play(.click)
            viewModel.revealSaveFolder(GameDetailsProfile.inspect(for: current).saveDirectory)
        case .editDetails:
            SoundEffectService.shared.play(.click)
            enterEditDetails()
        case .removeGame:
            SoundEffectService.shared.play(.click)
            askConfirm(.removeGame)
        case .storePage:
            guard let url = viewModel.storeMetadata[game.id]?.storeURL else { return }
            SoundEffectService.shared.play(.click)
            viewModel.openURL(url)
        case .attachSources:
            SoundEffectService.shared.play(.click)
            viewModel.locateSources(for: current)
        case .openLog:
            SoundEffectService.shared.play(.click)
            viewModel.revealLog(for: current)
        case .removeSources:
            SoundEffectService.shared.play(.click)
            askConfirm(.removeSources)
        }
    }

    /// Rebuild. A dimmed row still runs the build, so the Metal gate explains a refusal
    /// through the usual alert; a build that starts opens Add Game with its progress.
    private func rebuild(_ game: PortedGame) {
        guard !presentation.sourcesDetached else {
            SoundEffectService.shared.play(.error)
            return
        }
        SoundEffectService.shared.play(.click)
        viewModel.startBuild(for: game)
        if viewModel.isBuilding {
            onClose()
            onShowBuild()
        }
    }
}
