import SwiftUI
import NXLibraryCore

/// Selene's pill: glass at rest, solid focus colour with glow when focused.
struct SelenePillButton: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let title: String?
    var icon: MaterialIcon? = nil
    var minWidth: CGFloat = 180
    var height: CGFloat = 60
    let focused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: canvas.u(10)) {
                if let icon {
                    MaterialIconView(icon, size: 26)
                }
                if let title {
                    Text(title).seleneFont(21, .semibold)
                }
            }
            .foregroundColor(focused ? SeleneTheme.onFocus : SeleneTheme.ink)
            .padding(.horizontal, canvas.u(36))
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
