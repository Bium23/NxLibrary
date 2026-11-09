import SwiftUI
import AppKit
import NXLibraryCore

extension Notification.Name {
    static let nxControlsGamepadAction = Notification.Name("NXControlsGamepadAction")
}

/// Library navigation and the pinned engine's default game inputs are separate guides.
public struct ControlsView: View {
    let onClose: () -> Void
    let canHandleInput: () -> Bool
    @ObservedObject private var controller = GameControllerService.shared
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @State private var inGame = false
    @State private var focus = 0
    @State private var keyMonitor: Any?

    public init(canHandleInput: @escaping () -> Bool, onClose: @escaping () -> Void) {
        self.canHandleInput = canHandleInput
        self.onClose = onClose
    }

    private var rows: [(String, String)] {
        if inGame {
            // nxnative dm/host/front_mac.m: key_bit, on_key and push.
            return [
                (L10n.text("Left stick"), "W · A · S · D"),
                (L10n.text("D-pad"), L10n.text("Arrow keys")),
                ("A · B · X · Y", "J · K · U · I"),
                ("L · R", "Q · E"),
                ("ZL · ZR", "Z · C"),
                (L10n.text("Press left / right stick"), "F · G"),
                (L10n.text("Plus · Minus"), L10n.text("Return · Tab")),
                (L10n.text("Shake"), L10n.text("Hold Space")),
                (L10n.text("Right stick"), L10n.text("Shift + Arrow keys · Controller")),
                (L10n.text("Touchscreen"), L10n.text("Click and drag · Handheld mode")),
                ("Gamepad", L10n.text("USB or Bluetooth · Button positions follow the engine's layout")),
                ("Rumble", L10n.text("Depends on the game, build and controller")),
                // nxnative 48888df5 (home_quit.h): held for 2 s, a prompt; A quits as ⌘Q does, B or Home goes back.
                (L10n.text("Quit the game"), "⌘Q · Hold Home for 2 s, then A, in games built with the current engine")
            ]
        }
        return [
            ("Move", L10n.text("Arrows · D-pad or left stick")),
            ("Select", L10n.text("Return / Space · ") + controller.activeBrand.confirmButtonName),
            ("Back", L10n.text("Escape · ") + controller.activeBrand.cancelButtonName),
            ("Menu", "⌘K · Menu / Start"),
            ("Find a game", "⌘F · Hold View"),
            (L10n.text("Move a tile"), L10n.text("Hold Confirm on a Spotlight tile"))
        ]
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: canvas.u(12)) {
                        Text(L10n.text("Controls"))
                            .seleneFont(40)
                            .foregroundColor(SeleneTheme.ink)
                        Text(inGame ? L10n.text("Default game inputs. Older builds may differ.") : L10n.text("Navigate NX Library."))
                            .seleneFont(19)
                            .foregroundColor(SeleneTheme.ink60)
                            .padding(.bottom, canvas.u(18))
                        SeleneSegmented(selection: $inGame, options: [(false, "Library"), (true, "In game")])
                            .padding(.bottom, canvas.u(18))
                        SeleneOptionRow(icon: .gamepad, title: L10n.text("Controller"),
                            about: controller.isGamepadConnected ? controller.activeControllerName : L10n.text("Not connected"),
                            focused: focus == 0) {
                            Button(L10n.text("Detect")) { controller.refreshControllers() }
                                .buttonStyle(.plain)
                                .seleneFont(15, .semibold)
                                .foregroundColor(SeleneTheme.glyph)
                        }
                        .id(0)
                        ForEach(rows.indices, id: \.self) { index in
                            SeleneOptionRow(icon: nil, title: rows[index].0,
                                about: rows[index].1, focused: focus == index + 1) { EmptyView() }
                                .id(index + 1)
                        }
                    }
                    .padding(.horizontal, canvas.u(32))
                    .padding(.top, canvas.u(70))
                    .padding(.bottom, canvas.u(40))
                    .frame(maxWidth: max(700, canvas.u(1120)), alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .onChange(of: focus) { value in
                    withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(value, anchor: .center) }
                }
                .onChange(of: inGame) { _ in focus = 0; proxy.scrollTo(0, anchor: .top) }
            }
            SeleneHintsBar(left: [HintItem(.b, L10n.text("Back"), action: onClose)],
                right: [HintItem(.lb, L10n.text("Library")) { inGame = false }, HintItem(.rb, L10n.text("In game")) { inGame = true }])
        }
        .background(SeleneBackdrop())
        .environment(\.seleneMinimumFont, 12)
        .onAppear(perform: installKeyMonitor)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxControlsGamepadAction)) { note in
            if let action = note.object as? GamepadAction { handle(action) }
        }
    }

    private func handle(_ action: GamepadAction) {
        guard canHandleInput() else { return }
        switch action {
        case .cancel, .menu: onClose()
        case .tabPrevious, .navigateLeft: inGame = false
        case .tabNext, .navigateRight: inGame = true
        case .navigateUp: focus = max(0, focus - 1)
        case .navigateDown: focus = min(rows.count, focus + 1)
        case .confirm: if focus == 0 { controller.refreshControllers() }
        default: break
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard canHandleInput(), let window = event.window, !window.isSheet,
                  window.attachedSheet == nil, NSApp.modalWindow == nil,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 53: handle(.cancel)
            case 126: handle(.navigateUp)
            case 125: handle(.navigateDown)
            case 123, 12: handle(.tabPrevious)
            case 124, 14: handle(.tabNext)
            case 36, 76, 49: handle(.confirm)
            default: return event
            }
            return nil
        }
    }
}
