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
    /// False draws the pill dim: it still takes focus (a ring), but never the solid focus fill.
    var enabled: Bool = true
    /// Three dots after the title rising and falling like a wave ("Porting…").
    var waveDots = false
    let action: () -> Void

    var body: some View {
        let solid = focused && enabled
        Button(action: action) {
            HStack(spacing: canvas.u(10)) {
                if let icon {
                    MaterialIconView(icon, size: iconSize)
                }
                if let title {
                    Text(title).seleneFont(21)
                }
                if waveDots {
                    WaveDots()
                        .padding(.leading, canvas.u(-4))
                }
            }
            .foregroundColor(solid ? SeleneTheme.onFocus : (enabled ? SeleneTheme.ink : SeleneTheme.ink60))
            .padding(.horizontal, canvas.u(horizontalPadding))
            .frame(minWidth: canvas.u(minWidth), minHeight: canvas.u(height), maxHeight: canvas.u(height))
            .background(Capsule().fill(solid ? SeleneTheme.focus : SeleneTheme.glass))
            .overlay(Capsule().strokeBorder(focused && !solid ? SeleneTheme.focus : SeleneTheme.ink15,
                                            lineWidth: solid ? 0 : max(1, canvas.u(focused && !solid ? 2 : 1))))
            .shadow(color: solid ? SeleneTheme.focus.opacity(0.4) : .clear, radius: canvas.u(22))
            .scaleEffect(focused && !reduceMotion ? 1.06 : 1)
            // Focus eases across pills; the colour change is a fade, so it stays under reduce motion.
            .animation(SeleneTheme.cubicOut(0.26), value: focused)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Three small dots, each rising and falling a little after the one before, like
/// the crest of a wave. Still with Reduce motion.
struct WaveDots: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: canvas.u(4)) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = reduceMotion ? 0 : max(0, sin((time / 1.1) * 2 * .pi - Double(index) * 0.9))
                    Circle()
                        .frame(width: canvas.u(5), height: canvas.u(5))
                        .offset(y: canvas.u(-5) * wave)
                        .opacity(0.55 + 0.45 * wave)
                }
            }
            .frame(height: canvas.u(14), alignment: .bottom)
            .padding(.top, canvas.u(6))
        }
        .accessibilityHidden(true)
    }
}
