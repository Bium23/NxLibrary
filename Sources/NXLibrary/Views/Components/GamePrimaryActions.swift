import SwiftUI
import NXLibraryCore

/// Play/Options/favorite visual and input targets are identical across sources.
struct GamePrimaryActions: View {
    let primaryTitle: String
    var secondaryTitle = "Options"
    let isFavorite: Bool
    let focused: Int?
    var primaryEnabled = true
    let onAction: (Int) -> Void
    var onHover: (Int) -> Void = { _ in }
    @Environment(\.seleneCanvas) private var canvas
    var body: some View {
        HStack(spacing: canvas.u(14)) {
            pill(0, SelenePillButton(title: primaryTitle, height: 52, focused: focused == 0,
                                    enabled: primaryEnabled) { onAction(0) })
            pill(1, SelenePillButton(title: secondaryTitle, height: 52, focused: focused == 1) { onAction(1) })
            pill(2, SelenePillButton(title: nil, icon: isFavorite ? .favorite : .favoriteBorder,
                                    iconSize: 20, minWidth: 52, height: 52, horizontalPadding: 0,
                                    focused: focused == 2) { onAction(2) })
                .accessibilityLabel(isFavorite ? L10n.text("Remove from favorites") : L10n.text("Add to favorites"))
        }
    }
    private func pill<V: View>(_ index: Int, _ view: V) -> some View {
        view.frame(height: canvas.u(60)).onHover { if $0 { onHover(index) } }
    }
}
