import SwiftUI
import NXLibraryCore

/// Selene's pill: glass at rest, solid focus colour with glow when focused.
struct SelenePillButton: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let title: String?
    var icon: MaterialIcon? = nil
    var iconSize: CGFloat = 26
    var minWidth: CGFloat = 180
    var height: CGFloat = 60
    /// Selene's Padding="36,0"; the round Favorite pill uses 0.
    var horizontalPadding: CGFloat = 36
    let focused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: canvas.u(10)) {
                if let icon {
                    MaterialIconView(icon, size: iconSize)
                }
                if let title {
                    Text(title).seleneFont(21)
                }
            }
            .foregroundColor(focused ? SeleneTheme.onFocus : SeleneTheme.ink)
            .padding(.horizontal, canvas.u(horizontalPadding))
            .frame(minWidth: canvas.u(minWidth), minHeight: canvas.u(height), maxHeight: canvas.u(height))
            .background(Capsule().fill(focused ? SeleneTheme.focus : SeleneTheme.glass))
            .overlay(Capsule().strokeBorder(SeleneTheme.ink15, lineWidth: focused ? 0 : max(1, canvas.u(1))))
            .shadow(color: focused ? SeleneTheme.focus.opacity(0.4) : .clear, radius: canvas.u(22))
            .scaleEffect(focused ? 1.06 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: focused)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
