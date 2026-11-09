import SwiftUI
import AppKit
import NXLibraryCore

/// The settings a build offers that Game options has no row of its own for, drawn from the build's
/// `launcher.json`: a switch for a toggle, a value for a choice or a range. Up/Down move, Left/Right change a value,
/// A flips a switch or steps a value, B closes. A setting the player's env.txt sets is shown dim and does not change.
struct MoreSettingsPanel: View {
    @ObservedObject var viewModel: AppViewModel
    let game: PortedGame
    let onClose: () -> Void
    @State private var snapshot: GameSettingsSnapshot?
    @State private var focus = 0
    @State private var keyMonitor: Any?
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    init(viewModel: AppViewModel, game: PortedGame, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.game = game
        self.onClose = onClose
        _snapshot = State(initialValue: viewModel.settingsSnapshot(for: game))
    }

    private var rows: [LauncherSetting] {
        guard let snapshot else { return [] }
        return snapshot.extraSettings.filter { snapshot.visible($0.env) }
    }

    var body: some View {
        ZStack {
            SeleneTheme.scrim65.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { onClose() }
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.text("MORE SETTINGS")).seleneFont(15, .semibold).foregroundColor(SeleneTheme.ink60)
                        .padding(.leading, canvas.u(8))
                    Text(game.name).seleneFont(40).foregroundColor(SeleneTheme.ink).lineLimit(1)
                        .padding(.leading, canvas.u(6))
                        .padding(.bottom, canvas.u(14))
                    list
                }
                .frame(width: canvas.u(1040), alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, canvas.u(90)).padding(.bottom, canvas.u(20))
                SeleneHintsBar(left: [HintItem(.b, L10n.text("Back"), action: onClose)], right: [HintItem(.a, L10n.text("Select"))],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: installKeyMonitor)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxGameOptionsGamepadAction)) { note in
            if let action = note.object as? GamepadAction { handle(action) }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: canvas.u(8)) {
                    ForEach(Array(rows.enumerated()), id: \.element.env) { index, setting in
                        rowView(setting, focused: index == focus)
                            .id(setting.env).contentShape(Rectangle())
                            .onTapGesture { focus = index; change(setting, by: 1) }
                    }
                }
                .padding(.top, canvas.u(6)).padding(.bottom, canvas.u(24))
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: canvas.u(680))
            .onChange(of: focus) { index in
                guard rows.indices.contains(index) else { return }
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(rows[index].env, anchor: .center) }
            }
        }
    }

    private func value(_ setting: LauncherSetting) -> String {
        snapshot?.value(setting.env) ?? setting.defaultValue ?? ""
    }

    private func isFixed(_ setting: LauncherSetting) -> Bool {
        snapshot?.fixed.contains(setting.env) ?? false
    }

    private func about(_ setting: LauncherSetting) -> String {
        if isFixed(setting) { return L10n.text("Set in env.txt") }
        if let note = setting.note, !note.isEmpty { return L10n.text(note) }
        return L10n.text(setting.section)
    }

    private func rowView(_ setting: LauncherSetting, focused: Bool) -> some View {
        let current = value(setting)
        let label = L10n.text(GameSettingValues.label(setting, current))
        return SeleneOptionRow(icon: nil, title: L10n.text(setting.label), about: about(setting), focused: focused,
                               enabled: !isFixed(setting)) {
            if setting.kind == "toggle" {
                SeleneSwitch(isOn: .constant(current == setting.on)).allowsHitTesting(false)
            } else {
                SeleneValueChip(text: label)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text(setting.label))
        .accessibilityHint(about(setting))
        .accessibilityValue(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { change(setting, by: 1) }
    }

    private func change(_ setting: LauncherSetting, by delta: Int) {
        guard !isFixed(setting) else {
            SoundEffectService.shared.play(.error)
            return
        }
        SoundEffectService.shared.play(.click)
        let next = GameSettingValues.stepped(setting, from: value(setting), by: delta)
        viewModel.setGameSetting(setting.env, to: next, for: game)
        snapshot = viewModel.settingsSnapshot(for: game)
        focus = min(focus, max(0, rows.count - 1))
    }

    private func handle(_ action: GamepadAction) {
        let rows = self.rows
        switch action {
        case .navigateUp:
            if focus > 0 { focus -= 1; SoundEffectService.shared.play(.focus) }
        case .navigateDown:
            if focus < rows.count - 1 { focus += 1; SoundEffectService.shared.play(.focus) }
        case .navigateLeft, .navigateRight:
            // Left/Right change values; a switch changes with A.
            guard rows.indices.contains(focus), rows[focus].kind != "toggle" else { return }
            change(rows[focus], by: action == .navigateLeft ? -1 : 1)
        case .confirm:
            if rows.indices.contains(focus) { change(rows[focus], by: 1) }
        case .cancel, .secondaryAction, .menu:
            onClose()
        default:
            break
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.gameForSettingsSheet?.id == game.id, let window = event.window,
                  viewModel.gameWithInstallFailure == nil, viewModel.settingsNotice == nil,
                  !window.isSheet, window.attachedSheet == nil, NSApp.modalWindow == nil,
                  !(window.firstResponder is NSText),
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let action: GamepadAction
            switch event.keyCode {
            case 126: action = .navigateUp
            case 125: action = .navigateDown
            case 123: action = .navigateLeft
            case 124: action = .navigateRight
            case 36, 76, 49: action = .confirm
            case 53: action = .cancel
            default: return event
            }
            handle(action)
            return nil
        }
    }
}
