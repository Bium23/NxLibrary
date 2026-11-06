import NXLibraryCore
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
                    // Core Animation turns and breathes it (TileMotion), at the screen's rate and at no cost to
                    // the app between frames.
                    TileRingLayers(style: .init(
                        cornerRadius: cornerRadius,
                        focus: SeleneTheme.focus,
                        glowLine: canvas.u(4),
                        glowBlur: canvas.u(16),
                        ringLine: canvas.u(3),
                        hairline: max(0.5, canvas.u(1)),
                        hairInset: canvas.u(1),
                        margin: canvas.u(Self.glowMargin)))
                        .padding(-canvas.u(Self.glowMargin))
                        .allowsHitTesting(false)
                }
            }
        }
        .transition(.opacity)
    }

    /// Room round the tile for the glow's blur (16u) to fade out in.
    static let glowMargin: CGFloat = 40

    /// Selene's ring, still (Reduce motion): a solid focus border whose opacity mask (1 · 0.9 · 0.6 · 0.9 · 1)
    /// lies along `angle`, over a blurred glow. Every stop is the focus colour, so no part of the ring ever
    /// reads dark. `TileRingLayers` draws the same ring and turns it.
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
        // Flattened on the GPU (Metal), not on the CPU. The margin keeps the glow's blur inside the
        // flattened layer.
        .padding(canvas.u(Self.glowMargin))
        .drawingGroup()
        .padding(-canvas.u(Self.glowMargin))
        .allowsHitTesting(false)
    }
}

/// A diagonal light sweep across the tile: hold 0.6s, sweep until 2.4s, idle until 5s (`TileMotion`).
/// The band runs along the top-left → bottom-right diagonal, entering past one corner and leaving past the
/// other, so it never pops in or out. Played by Core Animation (`TileShineLayers`).
struct SeleneShine: View {
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let cornerRadius: CGFloat
    let active: Bool

    var body: some View {
        if active && !reduceMotion {
            TileShineLayers(cornerRadius: cornerRadius)
                .allowsHitTesting(false)
        }
    }
}
