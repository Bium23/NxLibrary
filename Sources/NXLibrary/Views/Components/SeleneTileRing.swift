import SwiftUI

/// Selene's active tile ring: a 3u ring with a rotating highlight and a pulsing glow.
struct SeleneTileRing: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let cornerRadius: CGFloat
    let active: Bool

    var body: some View {
        if active {
            if reduceMotion {
                ring(angle: 0, glow: 0.35)
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    ring(angle: (t.truncatingRemainder(dividingBy: 5)) / 5 * 360,
                         glow: Self.glowOpacity(at: t))
                }
            }
        }
    }

    /// 0.2 <-> 0.55 over 1.8s, sine in-out, autoreverse.
    static func glowOpacity(at t: TimeInterval) -> Double {
        let p = (t.truncatingRemainder(dividingBy: 3.6)) / 1.8
        let tri = p <= 1 ? p : 2 - p
        return 0.2 + 0.35 * (0.5 - 0.5 * cos(.pi * tri))
    }

    private func ring(angle: Double, glow: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            shape.strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(3))
                .blur(radius: canvas.u(16))
                .opacity(glow)
            shape.strokeBorder(SeleneTheme.focus.opacity(0.55), lineWidth: canvas.u(3))
            shape.strokeBorder(
                AngularGradient(
                    gradient: Gradient(colors: [.clear, .white.opacity(0.9), .clear, .clear]),
                    center: .center, angle: .degrees(angle)),
                lineWidth: canvas.u(3))
        }
        .allowsHitTesting(false)
    }
}

/// A diagonal light sweep across the tile: hold 0.6s, sweep until 2.4s, idle until 5s.
struct SeleneShine: View {
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let cornerRadius: CGFloat
    let active: Bool

    var body: some View {
        if active && !reduceMotion {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5)
                let raw = min(max((t - 0.6) / 1.8, 0), 1)
                let p = 0.5 - 0.5 * cos(.pi * raw)
                let x = p * 1.6 - 0.3
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.22), location: 0.5),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: UnitPoint(x: x - 0.25, y: 0),
                        endPoint: UnitPoint(x: x + 0.05, y: 0.4)))
                    .opacity(raw > 0 && raw < 1 ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
    }
}
