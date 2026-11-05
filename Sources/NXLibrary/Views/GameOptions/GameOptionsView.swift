import SwiftUI
import AppKit
import NXLibraryCore

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
    /// The build's settings and their values, for a build with saved choices; nil for an older build (`config`).
    @State private var snapshot: GameSettingsSnapshot?
    @State private var level: GameOptionsLevel = .main
    /// The focused row by identity; nil means the top row of the level.
    @State private var pickedRow: GameOptionsRow?
    @State private var confirm: ConfirmTarget?
    /// Change artwork is open over the list; it takes the input until B closes it.
    @State private var artworkOpen = false
    /// Change metadata, likewise.
    @State private var metadataOpen = false
    /// The Cheats panel, likewise.
    @State private var cheatsOpen = false
    @State private var savesOpen = false
    /// The Mods panel, likewise.
    @State private var modsOpen: Bool
    @State private var modsValue: String
    @State private var moreOpen = false
    /// The Cheats row's value: read from disk when Game options opens and when the panel closes, not on every draw.
    @State private var cheatsValue: String
    /// A panel over the list has the input.
    private var panelOpen: Bool { artworkOpen || metadataOpen || cheatsOpen || modsOpen || savesOpen || moreOpen }
    @State private var confirmFocus: SeleneConfirmButton = .cancel
    @State private var keyMonitor: Any?
    /// Row frames in the list's viewport, written while scrolling without redrawing.
    @State private var scrollBox = OptionsScrollBox()

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    enum ConfirmTarget: Equatable {
        case removeSources
        case removeGame
    }

    init(viewModel: AppViewModel, game: PortedGame, origin: GameOptionsOrigin,
         onClose: @escaping () -> Void, onShowBuild: @escaping () -> Void,
         onMove: @escaping () -> Void, opensMods: Bool = false) {
        self.viewModel = viewModel
        self.game = game
        self.origin = origin
        self.onClose = onClose
        self.onShowBuild = onShowBuild
        self.onMove = onMove
        supportsRenderScale = viewModel.supportsSetting("DM_RENDER_SCALE", for: game)
        _config = State(initialValue: viewModel.loadRuntimeConfig(for: game))
        _snapshot = State(initialValue: viewModel.settingsSnapshot(for: game))
        _cheatsValue = State(initialValue: viewModel.cheatRowValue(for: game))
        _modsValue = State(initialValue: viewModel.modsRowValue(for: game))
        _modsOpen = State(initialValue: opensMods)
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
            sourcesDetached: !GameResourceState.sourcesAvailable(for: game),
            // Mirrors GameDetailView.toolchainBlocked: a known report that does not pass, without the override.
            toolchainBlocked: viewModel.isCheckingEnvironment || (viewModel.compatibilityReport != nil && !viewModel.canPassToolchainGate),
            toolchainHint: viewModel.isCheckingEnvironment ? "Checking environment" : viewModel.toolchainGateSummary?.buildHint,
            hasStorePage: viewModel.storeMetadata[game.id]?.storeURL != nil,
            gameName: game.name,
            appPath: game.url.path,
            canDeleteBundle: game.canDeleteAppBundle(),
            cheatsValue: cheatsValue,
            modsValue: modsValue,
            settings: snapshot
        )
    }

    private var rows: [GameOptionsRow] {
        presentation.focusableRows(level: level, origin: origin)
    }

    /// The focused row, re-resolved against the rows of this draw so that rows
    /// appearing above it (a Store page arriving late) do not move the focus.
    private var focusedRow: GameOptionsRow? {
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
                SeleneHintsBar(left: [HintItem(.b, "Back")], right: [HintItem(.a, "Select")],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A panel (Change artwork, Change metadata, Cheats) takes the screen; the list never shows through.
            .opacity(panelOpen ? 0 : 1)
            .allowsHitTesting(!panelOpen)

            if artworkOpen {
                ChangeArtworkView(viewModel: viewModel, game: current) { artworkOpen = false }
                    .transition(.opacity)
                    .zIndex(2)
            }

            if metadataOpen {
                ChangeMetadataView(viewModel: viewModel, game: current) { metadataOpen = false }
                    .transition(.opacity)
                    .zIndex(2)
            }

            if cheatsOpen {
                CheatsPanel(viewModel: viewModel, game: current, onRebuild: {
                    cheatsOpen = false
                    rebuild(current)
                }, onClose: {
                    cheatsOpen = false
                    cheatsValue = viewModel.cheatRowValue(for: current)
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
                    snapshot = viewModel.settingsSnapshot(for: current)
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
            viewModel.prepareBuildEnvironmentIfNeeded()
        }
        .onDisappear(perform: removeKeyMonitor)
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
                // With the list's 6 top inset this keeps Selene's 20 under the name.
                .padding(.bottom, canvas.u(14))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: canvas.u(8)) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            entryView(entry, p, focused: focused)
                        }
                    }
                    // The clip would shave the first row's focus border.
                    .padding(.top, canvas.u(6))
                    .padding(.bottom, canvas.u(24))
                    // Rows are measured in the list's own space, which scrolling never changes.
                    .coordinateSpace(name: OptionsScrollBox.space)
                    .onPreferenceChange(OptionRowFrames.self) { scrollBox.frames = $0 }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: canvas.u(680))
                .onChange(of: focusedRow) { row in
                    // A focus that followed the wheel leaves the list where the user put it.
                    if scrollBox.holdScroll { scrollBox.holdScroll = false; return }
                    guard let row else { return }
                    withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                        proxy.scrollTo(row.rawValue, anchor: .center)
                    }
                }
            }
            .id(level)
        }
        .frame(width: canvas.u(1040), alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, canvas.u(90))
        .padding(.bottom, canvas.u(110))
        // Clicks inside the column are not clicks on the scrim; only the dimmed area outside closes.
        .contentShape(Rectangle())
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
                .foregroundColor(isSelene ? SeleneTheme.ink75 : SeleneTheme.glyph)
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
            // Stack spacing is 8u on each side, so 8u here makes the 24u gap before a danger zone.
            Color.clear.frame(height: canvas.u(8))
        }
    }

    /// Selene's headings are a soft ink, not its blue accent.
    private var isSelene: Bool { ThemeStore.shared.palette.id == SelenePaletteCatalog.defaultID }

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
        .background(GeometryReader { geometry in
            Color.clear.preference(key: OptionRowFrames.self,
                                   value: [row: geometry.frame(in: .named(OptionsScrollBox.space))])
        })
        .contentShape(Rectangle())
        .onTapGesture { activate(row) }
        .id(row.rawValue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityHint(p.about(row) ?? "")
        .accessibilityValue(accessibilityValue(row) ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activate(row) }
    }

    /// The state a VoiceOver user hears for a switch or a value chip.
    private func accessibilityValue(_ row: GameOptionsRow) -> String? {
        if row.isToggle { return toggleValue(row) ? "On" : "Off" }
        if row.isChoice { return choiceText(row) }
        if row == .cheats { return presentation.cheatsValue }
        if row == .mods { return presentation.modsValue }
        return nil
    }

    @ViewBuilder
    private func trailing(_ row: GameOptionsRow) -> some View {
        if row.isToggle {
            // The row takes the click; the switch only shows the state.
            SeleneSwitch(isOn: .constant(toggleValue(row))).allowsHitTesting(false)
        } else if row.isChoice {
            SeleneValueChip(text: choiceText(row))
        } else if row == .cheats || row == .mods {
            HStack(spacing: canvas.u(10)) {
                SeleneValueChip(text: row == .cheats ? presentation.cheatsValue : presentation.modsValue)
                MaterialIconView(.chevron, size: 24)
                    .foregroundColor(SeleneTheme.ink60)
            }
        } else if row.opensSubmenu {
            MaterialIconView(.chevron, size: 24)
                .foregroundColor(SeleneTheme.ink60)
        } else {
            EmptyView()
        }
    }

    private func toggleValue(_ row: GameOptionsRow) -> Bool {
        if let (setting, value) = settingValue(row) {
            return value == (setting.kind == "toggle" ? setting.on : row.onValue)
        }
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
        if let (setting, value) = settingValue(row) { return GameSettingValues.label(setting, value) }
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
        pickedRow = row
    }

    private func moveFocus(by delta: Int) {
        let rows = self.rows
        let previous = focusedRow
        var focus = GameOptionsFocus(row: pickedRow, in: rows)
        focus.move(by: delta, count: rows.count)
        pickedRow = focus.row(in: rows)
        if focusedRow != previous {
            SoundEffectService.shared.play(.focus)
        }
    }

    private func enterEditDetails() {
        // Pin the focus to the first row now; a Store page that arrives later goes above it without moving it.
        pickedRow = presentation.focusableRows(level: .editDetails, origin: origin).first
        level = .editDetails
        // The store link needs the store metadata; Details asks for it the same way.
        viewModel.loadStoreMetadata(for: current)
    }

    private func leaveEditDetails() {
        level = .main
        // Back on the main list, the focus returns to Edit details, where it was left.
        pickedRow = .editDetails
        SoundEffectService.shared.play(.focus)
    }

    // MARK: - Input

    /// Nothing in the panel takes key focus, so `onMoveCommand` cannot be relied on:
    /// a monitor maps arrows, Return/Space and Esc, and turns the wheel into steps.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { event in
            guard viewModel.gameForSettingsSheet?.id == game.id,
                  !viewModel.isUpdateOfferOpen,
                  !NativeMenuCommands.shared.isTracking,
                  !panelOpen,
                  viewModel.gameToClose == nil,
                  viewModel.gameWithInstallFailure == nil,
                  viewModel.alertMessage == nil, viewModel.settingsNotice == nil,
                  let window = event.window,
                  !window.isSheet,
                  window.attachedSheet == nil,
                  NSApp.modalWindow == nil,
                  !(window.firstResponder is NSText) else { return event }
            if event.type == .scrollWheel { return scroll(with: event) }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return event }
            switch event.keyCode {
            case 126: navigate(by: -1)
            case 125: navigate(by: 1)
            case 123: horizontal(by: -1)
            case 124: horizontal(by: 1)
            case 36, 76, 49: activateFocused()
            case 53: back()
            default: return event
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// The list scrolls natively; 0.3 s after the last wheel or trackpad event
    /// (momentum included) the focus settles on a row in view.
    private func scroll(with event: NSEvent) -> NSEvent? {
        guard confirm == nil else { return nil }
        scrollBox.settle?.cancel()
        scrollBox.window = event.window
        scrollBox.pointer = event.locationInWindow
        let work = DispatchWorkItem { settleFocusOnScroll() }
        scrollBox.settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        return event
    }

    /// Keeps the focus if its row is still fully in view; otherwise picks the
    /// row nearest the middle of the list, without scrolling to it.
    private func settleFocusOnScroll() {
        // Where the list is scrolled to is read from its NSScrollView, once, now:
        // measuring it on every frame made the scroll stutter.
        guard let clip = scrollBox.clipView() else { return }
        let viewport = clip.bounds.height
        let top = clip.isFlipped ? clip.bounds.minY
            : (clip.documentView?.frame.height ?? 0) - clip.bounds.maxY
        guard viewport > 0 else { return }
        let rows = self.rows
        let frames = scrollBox.frames
            .filter { rows.contains($0.key) }
            .mapValues { $0.offsetBy(dx: 0, dy: -top) }
        if let row = focusedRow, let frame = frames[row], frame.minY >= 0, frame.maxY <= viewport { return }
        let inView = frames.filter { $0.value.maxY > 0 && $0.value.minY < viewport }
        guard let nearest = inView.min(by: {
            abs($0.value.midY - viewport / 2) < abs($1.value.midY - viewport / 2)
        })?.key, nearest != focusedRow else { return }
        scrollBox.holdScroll = true
        setFocus(nearest)
        SoundEffectService.shared.play(.focus)
    }

    private func handleGamepad(_ action: GamepadAction) {
        // Change artwork and Change metadata read the same notifications while open.
        guard !panelOpen else { return }
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

    /// A setting row of a build with saved choices, with the value that applies now.
    private func settingValue(_ row: GameOptionsRow) -> (LauncherSetting, String)? {
        guard let snapshot, let key = row.settingKey, let setting = snapshot.setting(key) else { return nil }
        return (setting, snapshot.value(key) ?? setting.defaultValue ?? "")
    }

    /// Changes a setting row of a build with saved choices: a switch flips, a value steps. A row env.txt sets
    /// does not change.
    private func changeSetting(_ row: GameOptionsRow, by delta: Int) {
        guard let (setting, value) = settingValue(row) else { return }
        guard !presentation.isFixed(row) else {
            SoundEffectService.shared.play(.error)
            return
        }
        SoundEffectService.shared.play(.click)
        let next: String
        if row.isToggle, setting.kind != "toggle" {
            // A two-option choice drawn as a switch (Display mode, Upscaling).
            next = value == row.onValue
                ? (setting.options?.first { $0.value != row.onValue }?.value ?? value)
                : row.onValue
        } else {
            next = GameSettingValues.stepped(setting, from: value, by: delta)
        }
        viewModel.setGameSetting(setting.env, to: next, for: current)
        snapshot = viewModel.settingsSnapshot(for: current)
    }

    /// Left/Right on a choice row: step backwards or forwards.
    private func adjust(_ row: GameOptionsRow, by delta: Int) {
        if snapshot != nil, row.settingKey != nil {
            changeSetting(row, by: delta)
            return
        }
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
        if snapshot != nil, row.settingKey != nil {
            changeSetting(row, by: 1)
            return
        }
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
            // Close only once the hidden flag is saved: a failed save leaves the game listed.
            let nowHidden = viewModel.libraryGames.first { $0.id == game.id }?.isHidden ?? false
            if hiding && nowHidden { onClose() }
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
        case .consoleMode, .language, .rumbleStrength, .renderScale, .frameRate, .gameUpscaler:
            adjust(row, by: 1)
        case .moreSettings:
            SoundEffectService.shared.play(.click)
            moreOpen = true
        case .rumble:
            SoundEffectService.shared.play(.click)
            config.rumble.toggle()
        case .restoreDefaults:
            SoundEffectService.shared.play(.click)
            if snapshot != nil {
                viewModel.restoreGameDefaults(for: current)
                snapshot = viewModel.settingsSnapshot(for: current)
            } else {
                config = viewModel.settingsStore?.settings.gameDefaults ?? GameRuntimeConfig()
            }
        case .cheats:
            SoundEffectService.shared.play(.click)
            cheatsOpen = true
        case .mods:
            SoundEffectService.shared.play(.click)
            modsOpen = true
        case .rebuild:
            rebuild(current)
        case .showInFinder:
            SoundEffectService.shared.play(.click)
            viewModel.revealInFinder(url: current.url)
        case .openSaves:
            SoundEffectService.shared.play(.click)
            savesOpen = true
        case .editDetails:
            SoundEffectService.shared.play(.click)
            enterEditDetails()
        case .removeGame:
            SoundEffectService.shared.play(.click)
            askConfirm(.removeGame)
        case .changeArtwork:
            SoundEffectService.shared.play(.click)
            // The official name helps the cover search, as on the Collection.
            viewModel.loadStoreMetadata(for: current)
            artworkOpen = true
        case .changeMetadata:
            SoundEffectService.shared.play(.click)
            // Automatic is the store's metadata; ask for it if it is not here yet.
            viewModel.loadStoreMetadata(for: current)
            metadataOpen = true
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

/// Scroll bookkeeping for Game options. A reference type, so writing it on every
/// scroll frame does not redraw the panel.
private final class OptionsScrollBox {
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

private struct OptionRowFrames: PreferenceKey {
    static var defaultValue: [GameOptionsRow: CGRect] = [:]
    static func reduce(value: inout [GameOptionsRow: CGRect], nextValue: () -> [GameOptionsRow: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
