import SwiftUI

/// Selene's active tile ring: a 3u ring with a rotating highlight and a pulsing glow.
struct SeleneTileRing: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let cornerRadius: CGFloat
    let active: Bool

    var body: some View {
        // The ring fades between tiles instead of jumping (the row animates the selection).
        Group {
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
        .transition(.opacity)
    }

    /// 0.2 <-> 0.55 over 1.8s, sine in-out, autoreverse.
    static func glowOpacity(at t: TimeInterval) -> Double {
        let p = (t.truncatingRemainder(dividingBy: 3.6)) / 1.8
        let tri = p <= 1 ? p : 2 - p
        return 0.2 + 0.35 * (0.5 - 0.5 * cos(.pi * tri))
    }

    /// Selene's ring: a solid focus border whose opacity mask (1 · 0.9 · 0.6 · 0.9 · 1)
    /// turns once every 5 s, over a blurred glow. Every stop is the focus colour,
    /// so no part of the ring ever reads dark.
    private func ring(angle: Double, glow: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let radians = angle * .pi / 180
        let dx = cos(radians) * 0.5, dy = sin(radians) * 0.5
        let focus = SeleneTheme.focus
        return ZStack {
            shape.strokeBorder(focus, lineWidth: canvas.u(4))
                .blur(radius: canvas.u(16))
                .opacity(glow)
            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: focus, location: 0),
                        .init(color: focus.opacity(0.9), location: 0.25),
                        .init(color: focus.opacity(0.6), location: 0.5),
                        .init(color: focus.opacity(0.9), location: 0.75),
                        .init(color: focus, location: 1)
                    ],
                    startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                    endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)),
                lineWidth: canvas.u(3))
            shape.strokeBorder(Color.white.opacity(0.18), lineWidth: max(0.5, canvas.u(1)))
                .padding(canvas.u(1))
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }
}

/// A diagonal light sweep across the tile: hold 0.6s, sweep until 2.4s, idle until 5s.
/// The band runs along the top-left → bottom-right diagonal, entering past one
/// corner and leaving past the other, so it never pops in or out. Selene's glint
/// (Main.xaml Shine): a thin core at 0.18 white with faint 0.04 shoulders.
struct SeleneShine: View {
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let cornerRadius: CGFloat
    let active: Bool

    var body: some View {
        if active && !reduceMotion {
            Sweep(cornerRadius: cornerRadius)
        }
    }

    /// Half the band's width, in diagonal units (0 = top-left corner, 1 = bottom-right).
    static let halfWidth = 0.3

    /// The band's centre along the diagonal `t` seconds after the tile was selected.
    static func centre(at t: TimeInterval) -> Double {
        let cycle = t.truncatingRemainder(dividingBy: 5)
        let raw = min(max((cycle - 0.6) / 1.8, 0), 1)
        let eased = 0.5 - 0.5 * cos(.pi * raw)
        return -halfWidth + eased * (1 + 2 * halfWidth)
    }

    private struct Sweep: View {
        let cornerRadius: CGFloat
        /// Each selection starts its own cycle, so the light always comes in from the corner.
        @State private var start = Date()

        var body: some View {
            TimelineView(.animation) { context in
                let c = SeleneShine.centre(at: context.date.timeIntervalSince(start))
                let w = SeleneShine.halfWidth
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: 0),
                            .init(color: .white.opacity(0.04), location: 0.3),
                            .init(color: .white.opacity(0.18), location: 0.5),
                            .init(color: .white.opacity(0.04), location: 0.7),
                            .init(color: .white.opacity(0), location: 1)
                        ],
                        startPoint: UnitPoint(x: c - w, y: c - w),
                        endPoint: UnitPoint(x: c + w, y: c + w)))
                    .allowsHitTesting(false)
            }
        }
    }
}
