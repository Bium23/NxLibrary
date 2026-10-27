import SwiftUI
import NXLibraryCore

public struct MenuOverlayView: View {
    @ObservedObject public var router: AppRouter
    public let onSelect: (MenuAction) -> Void

    public init(router: AppRouter, onSelect: @escaping (MenuAction) -> Void) {
        self.router = router
        self.onSelect = onSelect
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { router.closeMenu() }

            VStack(spacing: 18) {
                Text(router.menuSelection.selected.title)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2.2)
                    .textCase(.uppercase)
                    .foregroundColor(SeleneTheme.ink.opacity(0.78))

                HStack(spacing: 38) {
                    ForEach(MenuAction.allCases) { action in
                        Button {
                            router.menuSelection.selected = action
                            onSelect(action)
                        } label: {
                            Image(systemName: action.icon)
                                .font(.system(size: router.menuSelection.selected == action ? 26 : 21,
                                              weight: .medium))
                                .foregroundColor(router.menuSelection.selected == action
                                                 ? SeleneTheme.canvas
                                                 : SeleneTheme.ink.opacity(0.55))
                                .frame(width: router.menuSelection.selected == action ? 78 : 58,
                                       height: router.menuSelection.selected == action ? 78 : 58)
                                .background(router.menuSelection.selected == action
                                            ? SeleneTheme.focus
                                            : SeleneTheme.ink.opacity(0.08))
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(
                                    SeleneTheme.ink.opacity(router.menuSelection.selected == action ? 0 : 0.13),
                                    lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(action.title)
                    }
                }
            }
            .padding(.bottom, 90)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .transition(.opacity)
    }
}
