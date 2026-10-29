import SwiftUI
import NXLibraryCore

/// Selene's control center: the screen dimmed at 0.55, one row of icon buttons
/// along the bottom (centre 68u above the bottom edge of the 1080u stage), the
/// focused item's name above a 3u white ring. Power opens its pills stacked above
/// its button.
///
/// Keyboard arrows, Return and Space go to the shell as `GamepadAction`s, so the
/// keyboard and the controller share one path. Mouse: hover focuses, click
/// activates, a click on the scrim closes. Esc reaches the shell's exit command.
struct MenuOverlayView: View {
    @ObservedObject var router: AppRouter
    /// Keyboard input: arrows, Return and Space.
    let onInput: (GamepadAction) -> Void
    /// A click on a row button; the shell runs it.
    let onSelect: (MenuAction) -> Void
    /// A click on a Power pill; the shell runs it.
    let onSelectPower: (PowerAction) -> Void

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var settingsReduceMotion
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var presented = false

    /// Gates scale and movement only; opacity always animates.
    private var reduceMotion: Bool {
        settingsReduceMotion || accessibilityReduceMotion
    }

    private var powerOpen: Bool { router.menuSelection.isPowerOpen }

    // Selene units. The row's centre sits at y = 1012u of 1080u.
    private let buttonSize: CGFloat = 64
    private let focusRingSize: CGFloat = 76
    private let focusRingWidth: CGFloat = 3
    private let rowGap: CGFloat = 16
    private let labelBand: CGFloat = 26
    private let labelGap: CGFloat = 18
    private let rowBottom: CGFloat = 36
    private let iconSize: CGFloat = 28

    var body: some View {
        ZStack(alignment: .bottom) {
            SeleneTheme.scrim.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { router.closeMenu() }

            row
                .padding(.bottom, canvas.u(rowBottom))

            SeleneHintsBar(left: [HintItem(.b, "Close")], right: [HintItem(.a, "Select")], bottom: 40)
        }
        .onMoveCommand(perform: handleMove)
        .seleneActivationKeys { onInput(.confirm) }
        .onAppear { presented = true }
    }

    // MARK: - Row

    private var row: some View {
        HStack(alignment: .bottom, spacing: canvas.u(rowGap)) {
            ForEach(Array(MenuAction.allCases.enumerated()), id: \.element) { index, action in
                button(action, index: index)
            }
        }
    }

    private func button(_ action: MenuAction, index: Int) -> some View {
        let isFocused = router.menuSelection.selected == action

        return Button {
            router.menuSelection.selected = action
            onSelect(action)
        } label: {
            VStack(spacing: 0) {
                Text(action.title)
                    .seleneFont(19, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: canvas.u(labelBand), alignment: .bottom)
                    .opacity(isFocused ? 1 : 0)
                    .animation(SeleneTheme.focusIn, value: isFocused)
                    .offset(y: isFocused || reduceMotion ? 0 : canvas.u(6))
                    .padding(.bottom, canvas.u(labelGap))

                ZStack {
                    Circle()
                        .fill(isFocused ? SeleneTheme.glass : Color.clear)
                        .frame(width: canvas.u(buttonSize), height: canvas.u(buttonSize))
                    Circle()
                        .strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(focusRingWidth))
                        .frame(width: canvas.u(focusRingSize), height: canvas.u(focusRingSize))
                        .opacity(isFocused ? 1 : 0)
                        .animation(SeleneTheme.focusIn, value: isFocused)
                    MaterialIconView(action.icon, size: iconSize)
                        .foregroundColor(SeleneTheme.ink)
                }
                .frame(width: canvas.u(buttonSize), height: canvas.u(buttonSize))
                .scaleEffect(isFocused && !reduceMotion ? 1.06 : 1)
                .animation(reduceMotion ? nil : SeleneTheme.quick, value: isFocused)
            }
            .frame(width: canvas.u(buttonSize))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering, !powerOpen { router.menuSelection.selected = action }
        }
        .overlay(alignment: .bottom) {
            if action == .power, powerOpen {
                powerPills
                    .transition(.opacity)
                    .offset(y: -canvas.u(labelBand + labelGap + buttonSize + 14))
            }
        }
        .accessibilityLabel(action.title)
        .accessibilityAddTraits(isFocused ? [.isSelected] : [])
        .opacity(presented ? 1 : 0)
        .offset(y: presented || reduceMotion ? 0 : canvas.u(24))
        .animation(entrance(index), value: presented)
        .animation(SeleneTheme.quick, value: powerOpen)
    }

    private func entrance(_ index: Int) -> Animation {
        let curve = SeleneTheme.cubicOut(0.26)
        // Selene's icons rise one after another, 25 ms apart.
        return reduceMotion ? .easeOut(duration: 0.12) : curve.delay(Double(index) * 0.025)
    }

    // MARK: - Power pills

    private var powerPills: some View {
        VStack(spacing: canvas.u(12)) {
            ForEach(PowerAction.allCases) { action in
                SelenePillButton(title: action.title,
                                 icon: action.icon,
                                 minWidth: 240,
                                 focused: router.menuSelection.power == action) {
                    router.menuSelection.power = action
                    onSelectPower(action)
                }
                .onHover { hovering in
                    if hovering { router.menuSelection.power = action }
                }
                .accessibilityLabel(action.title)
            }
        }
    }

    // MARK: - Keyboard

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left: onInput(.navigateLeft)
        case .right: onInput(.navigateRight)
        case .up: onInput(.navigateUp)
        case .down: onInput(.navigateDown)
        default: break
        }
    }
}
