import SwiftUI
import NXLibraryCore

/// Arrives a beat after its screen changes: holds `delay`, then fades in while
/// rising `rise` Selene units. Give the view an `.id` per item so each change
/// replays it. Reduce motion keeps the fade and drops the rise.
struct SeleneReveal: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let delay: Double
    var rise: CGFloat = 16

    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : canvas.u(rise))
            .onAppear {
                withAnimation(SeleneTheme.cubicOut(0.6).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func seleneReveal(delay: Double, rise: CGFloat = 16) -> some View {
        modifier(SeleneReveal(delay: delay, rise: rise))
    }
}
