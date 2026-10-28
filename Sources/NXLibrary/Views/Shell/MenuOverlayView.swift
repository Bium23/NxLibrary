import SwiftUI
import AppKit
import NXLibraryCore

public struct MenuOverlayView: View {
    @ObservedObject public var router: AppRouter
    public let onSelect: (MenuAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.seleneReduceMotion) private var settingsReduceMotion

    @State private var presented = false

    private var reduceMotion: Bool {
        accessibilityReduceMotion || settingsReduceMotion
    }

    public init(router: AppRouter, onSelect: @escaping (MenuAction) -> Void) {
        self.router = router
        self.onSelect = onSelect
    }

    public var body: some View {
        ZStack {
            backdrop
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { router.closeMenu() }

            menu
                .padding(.bottom, 90)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .transition(.opacity)
        .onAppear { presented = true }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        Group {
            if reduceTransparency {
                // Opaque fallback when the system asks for reduced transparency.
                SeleneTheme.canvasRaised.opacity(0.98)
            } else {
                ZStack {
                    // Real backdrop blur (~20–24 pt equivalent) so the library stays recognizable.
                    MenuBackdropBlur()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    Color.black.opacity(0.62)
                }
            }
        }
        .opacity(presented ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : SeleneTheme.standard,
                   value: presented)
    }

    // MARK: - Menu

    private var menu: some View {
        VStack(spacing: 20) {
            Text(router.menuSelection.selected.title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(2.2)
                .textCase(.uppercase)
                .foregroundColor(SeleneTheme.ink.opacity(0.72))
                .opacity(presented ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.12) : SeleneTheme.menu,
                           value: presented)

            HStack(alignment: .top, spacing: 22) {
                ForEach(Array(MenuAction.allCases.indices), id: \.self) { index in
                    menuItem(MenuAction.allCases[index], index: index)
                }
            }
        }
    }

    private func menuItem(_ action: MenuAction, index: Int) -> some View {
        let isFocused = router.menuSelection.selected == action

        return Button {
            router.menuSelection.selected = action
            onSelect(action)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isFocused ? SeleneTheme.focus : SeleneTheme.ink.opacity(0.08))
                    Circle()
                        .strokeBorder(SeleneTheme.ink.opacity(isFocused ? 0 : 0.14),
                                      lineWidth: 1)
                    Image(systemName: action.icon)
                        .font(.system(size: isFocused ? 24 : 20, weight: .medium))
                        .foregroundColor(isFocused ? SeleneTheme.canvas
                                         : SeleneTheme.ink.opacity(0.6))
                }
                .frame(width: isFocused ? 64 : 56, height: isFocused ? 64 : 56)
                .frame(width: 64, height: 64)

                Text(action.title)
                    .font(.system(size: 10.5, weight: isFocused ? .semibold : .medium))
                    .foregroundColor(isFocused ? SeleneTheme.ink : SeleneTheme.ink.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(width: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityAddTraits(isFocused ? [.isSelected] : [])
        .opacity(presented ? 1 : 0)
        .offset(y: presented || reduceMotion ? 0 : 16)
        .animation(entranceAnimation(for: index), value: presented)
        .animation(reduceMotion ? nil : SeleneTheme.quick,
                   value: router.menuSelection.selected)
    }

    private func entranceAnimation(for index: Int) -> Animation? {
        guard !reduceMotion else { return .easeOut(duration: 0.12) }
        // 20 ms stagger for at most six items keeps the entrance quiet and predictable.
        return SeleneTheme.menu.delay(Double(min(index, 5)) * 0.02)
    }
}

// MARK: - Backdrop blur

private struct MenuBackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.material = .hudWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
    }
}
