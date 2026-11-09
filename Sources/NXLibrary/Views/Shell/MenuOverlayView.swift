import SwiftUI
import NXLibraryCore

/// Selene's control center (MenuScreen.cs): the screen dimmed at 0.55, one row of
/// icon buttons along the bottom, the focused item's name above a white ring.
/// Power opens its pills stacked above its button.
///
/// Keyboard input (arrows, Return, Space, Esc) is taken by the shell's key monitor
/// while the menu is open and sent through `menuInput`, the same path as the
/// controller. Mouse: hover focuses, click activates, a click on the scrim closes.
struct MenuOverlayView: View {
    @ObservedObject var router: AppRouter
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

    // Selene units (MenuScreen.cs): 96u cells with no gap, a 70u dot with a 3u
    // ring, the bar 70u above the bottom edge, so the dot's centre is 105u up
    // (y = 975u of 1080u).
    private let cellWidth: CGFloat = 96
    private let dotSize: CGFloat = 70
    private let ringWidth: CGFloat = 3
    private let iconSize: CGFloat = 34
    private let labelBand: CGFloat = 26
    /// Between the name and the top of the ring (Selene: the pill sits Ring + 12 above the cell's bottom).
    private let labelGap: CGFloat = 12
    private let rowBottom: CGFloat = 70
    private let focusedScale: CGFloat = 1.1
    /// Above the Power pills' bottom edge, the gap to the name.
    private let pillsGap: CGFloat = 14

    var body: some View {
        ZStack(alignment: .bottom) {
            SeleneTheme.scrim.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { router.closeMenu() }

            row
                .padding(.bottom, canvas.u(rowBottom))

            // Where the screen underneath had its hints, which step aside while this is open.
            SeleneHintsBar(left: [HintItem(.b, L10n.text("Close"))], right: [HintItem(.a, L10n.text("Select"))],
                           bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
        }
        .onAppear { presented = true }
    }

    // MARK: - Row

    private var row: some View {
        HStack(alignment: .bottom, spacing: 0) {
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
                    .seleneFont(18, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: canvas.u(labelBand), alignment: .bottom)
                    .opacity(isFocused ? 1 : 0)
                    .offset(y: isFocused || reduceMotion ? 0 : canvas.u(6))
                    .animation(SeleneTheme.focusIn, value: isFocused)
                    .padding(.bottom, canvas.u(labelGap))

                ZStack {
                    Circle()
                        .fill(SeleneTheme.ink.opacity(isFocused ? 0.12 : 0))
                        .frame(width: canvas.u(dotSize), height: canvas.u(dotSize))
                        .animation(SeleneTheme.focusIn, value: isFocused)
                    Circle()
                        .strokeBorder(SeleneTheme.ink, lineWidth: canvas.u(ringWidth))
                        .frame(width: canvas.u(dotSize), height: canvas.u(dotSize))
                        .opacity(isFocused ? 1 : 0)
                        .animation(SeleneTheme.focusIn, value: isFocused)
                    MaterialIconView(action.icon, size: iconSize)
                        .foregroundColor(SeleneTheme.ink)
                }
                .frame(width: canvas.u(dotSize), height: canvas.u(dotSize))
                .scaleEffect(isFocused && !reduceMotion ? focusedScale : 1)
                .animation(reduceMotion ? nil : SeleneTheme.quick, value: isFocused)
            }
            .frame(width: canvas.u(cellWidth))
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
                    .offset(y: -canvas.u(labelBand + labelGap + dotSize + pillsGap))
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
}
