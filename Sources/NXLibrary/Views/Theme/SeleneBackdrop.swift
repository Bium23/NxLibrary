import SwiftUI
import AppKit
import NXLibraryCore

/// What the backdrop draws, set once on the shell from settings.
struct SeleneBackdropStyle: Equatable {
    var wallpaperURL: URL?
    var sizing: BackgroundSizing = .fill
    var animated = true
}

private struct SeleneBackdropStyleKey: EnvironmentKey {
    static let defaultValue = SeleneBackdropStyle()
}

extension EnvironmentValues {
    var seleneBackdropStyle: SeleneBackdropStyle {
        get { self[SeleneBackdropStyleKey.self] }
        set { self[SeleneBackdropStyleKey.self] = newValue }
    }
}

/// Decoded wallpapers, kept so a redraw never reads the file again.
final class WallpaperImageCache {
    static let shared = WallpaperImageCache()
    private let cache = NSCache<NSURL, NSImage>()

    func image(at url: URL) -> NSImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// Selene's base layer (Main.xaml): scrim, the palette's base gradient and the
/// wallpaper. Without a wallpaper the theme's own backdrop shows (Selene's
/// moonlight, `MoonlightBackdrop`): moving when on and motion is allowed, still otherwise.
/// The home draws the gradient and wallpaper whole (`.home`); other screens at 0.6, darker.
struct SeleneBackdrop: View {
    @Environment(\.seleneBackdropStyle) private var style
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.seleneCanvas) private var canvas

    /// The base gradient's and the wallpaper's opacity.
    var baseOpacity = 0.6
    var wallpaperOpacity = 0.6
    /// Covered (a game's art over it): the moonlight holds still and costs nothing.
    var still = false

    func still(_ on: Bool) -> SeleneBackdrop {
        var copy = self
        copy.still = on
        return copy
    }

    /// Spotlight (Selene's SeleneHubGameBackground): both whole.
    static let home = SeleneBackdrop(baseOpacity: 1, wallpaperOpacity: 1)
    /// Collection (Selene's library): the gradient whole, the wallpaper at 0.6.
    static let library = SeleneBackdrop(baseOpacity: 1, wallpaperOpacity: 0.6)

    var body: some View {
        ZStack {
            SeleneTheme.scrim
            Rectangle().fill(SeleneTheme.baseGradient).opacity(baseOpacity)
            if let url = style.wallpaperURL, let image = WallpaperImageCache.shared.image(at: url) {
                wallpaper(image)
                    .opacity(wallpaperOpacity)
            } else {
                MoonlightBackdrop(accent: SeleneTheme.glyph, ink: SeleneTheme.ink, unit: canvas.u(1),
                                  moving: style.animated && !reduceMotion && !still)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func wallpaper(_ image: NSImage) -> some View {
        switch style.sizing {
        case .fill:
            Color.clear
                .overlay(Image(nsImage: image).resizable().interpolation(.high)
                    .aspectRatio(contentMode: .fill))
                .clipped()
        case .fit:
            Image(nsImage: image).resizable().interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .stretch:
            Image(nsImage: image).resizable().interpolation(.high)
        }
    }
}

/// The theme's own backdrop, after Selene's looping video: a beam of the
/// theme's accent falling from the top left onto a pool of light on the floor,
/// breathing; from the pool a stream of motes rises to the right with a soft
/// glowing wake along it, a brighter swell running down the wake; far motes
/// fine and slow, near ones large, soft and bobbing. Every look is a number
/// below, in the theme's colors; 30 fps, or one still frame.
struct MoonlightBackdrop: View {
    let accent: Color
    let ink: Color
    /// One Selene unit in points (the canvas's), so a small preview scales down.
    let unit: CGFloat
    var moving = true

    // MARK: Look

    /// Beam: centre and radii as fractions of the window, strength at its heart and half way.
    static let beam = (x: 0.17, y: -0.06, rx: 0.13, ry: 0.55, core: 0.5, mid: 0.16)
    /// The pool where the beam meets the floor.
    static let pool = (x: 0.2, y: 0.86, rx: 0.22, ry: 0.075, strength: 0.34)
    /// Beam and pool breathe together: lowest share of full, period (s).
    static let breath = (low: 0.7, period: 7.0)
    /// Wash around the beam, and the floor's haze (centre, radii, strength).
    static let wash = (x: 0.16, y: -0.12, rx: 0.6, ry: 1.1, strength: 0.14)
    static let haze = (x: 0.45, y: 1.04, rx: 0.9, ry: 0.3, strength: 0.16)
    /// The stream's line: its height at the left and right edges, the bow of
    /// its S, and how far its waves travel (period, s).
    static let stream = (left: 0.84, right: 0.42, bow: 0.035, wavePeriod: 40.0)
    /// The wake along the stream: blobs, their radius (window heights), strength,
    /// and the swell that runs along it (width as a share of the stream, period s).
    static let wake = (blobs: 34, radius: 0.085, strength: 0.07, swell: 0.22, swellPeriod: 11.0)

    struct Layer {
        let count: Int
        /// Radius in Selene units, peak opacity, speed (share of the stream per second).
        let radius: ClosedRange<Double>
        let alpha: ClosedRange<Double>
        let speed: ClosedRange<Double>
        /// Spread across the stream (window heights).
        let spread: Double
        /// Bob (Selene units) and its period (s).
        let bob: ClosedRange<Double>
        /// Soft discs (bokeh) instead of sharp points.
        let soft: Bool
    }

    static let layers = [
        Layer(count: 150, radius: 0.5...1.4, alpha: 0.35...0.85, speed: 0.012...0.025, spread: 0.07,
              bob: 2...6, soft: false),
        Layer(count: 40, radius: 1.6...3.2, alpha: 0.3...0.6, speed: 0.022...0.04, spread: 0.11,
              bob: 6...14, soft: true),
        Layer(count: 14, radius: 6...16, alpha: 0.16...0.34, speed: 0.03...0.05, spread: 0.26,
              bob: 12...28, soft: true)
    ]
    /// Of every mote, the share drawn in the ink (white-ish) rather than the accent.
    static let inkShare = 0.28

    // MARK: Drawing

    private struct Mote {
        let start, offset, radius, alpha, speed, bob, bobPeriod, phase, twinkle: Double
        let soft, inked: Bool
    }

    private static let motes: [Mote] = {
        var random = SplitMix(seed: 0x5E1E4E)
        var motes: [Mote] = []
        for layer in layers {
            for _ in 0..<layer.count {
                func pick(_ range: ClosedRange<Double>) -> Double {
                    range.lowerBound + (range.upperBound - range.lowerBound) * random.unit()
                }
                // Box-Muller: most motes near the stream's line, a few further out.
                let gauss = (-2 * log(max(random.unit(), 1e-9))).squareRoot() * cos(2 * .pi * random.unit())
                motes.append(Mote(start: random.unit(), offset: gauss * layer.spread, radius: pick(layer.radius),
                                  alpha: pick(layer.alpha), speed: pick(layer.speed), bob: pick(layer.bob),
                                  bobPeriod: 6 + random.unit() * 7, phase: random.unit() * 2 * .pi,
                                  twinkle: 0.8 + random.unit() * 1.6, soft: layer.soft,
                                  inked: random.unit() < inkShare))
            }
        }
        return motes
    }()

    @State private var breathing = false

    /// The glows are drawn once and the beam breathes by its layer's opacity; only
    /// the wake and the motes redraw each frame.
    var body: some View {
        ZStack {
            Canvas { context, size in drawGlows(&context, size: size) }
            Canvas { context, size in drawBeam(&context, size: size) }
                .opacity(moving ? (breathing ? 1 : Self.breath.low) : 0.85)
                .onAppear { startBreathing() }
                .onChange(of: moving) { _ in startBreathing() }
            if moving {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    Canvas { context, size in
                        drawStream(&context, size: size, t: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
            } else {
                Canvas { context, size in drawStream(&context, size: size, t: 0) }
            }
        }
    }

    private func startBreathing() {
        guard moving else { breathing = false; return }
        withAnimation(.easeInOut(duration: Self.breath.period / 2).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }

    /// The stream's height (window share) at `x` (0 left, 1 right) and time `t`: rising, with a travelling S.
    static func streamY(_ x: Double, _ t: TimeInterval) -> Double {
        stream.left + (stream.right - stream.left) * x
            + stream.bow * sin(2 * .pi * (x * 1.1 - t / stream.wavePeriod))
    }

    private func drawGlows(_ context: inout GraphicsContext, size: CGSize) {
        glow(&context, size: size, x: Self.wash.x, y: Self.wash.y, rx: Self.wash.rx, ry: Self.wash.ry,
             stops: fade(Self.wash.strength))
        glow(&context, size: size, x: Self.haze.x, y: Self.haze.y, rx: Self.haze.rx, ry: Self.haze.ry,
             stops: fade(Self.haze.strength))
    }

    private func drawBeam(_ context: inout GraphicsContext, size: CGSize) {
        let b = Self.beam
        glow(&context, size: size, x: b.x, y: b.y, rx: b.rx, ry: b.ry,
             stops: [.init(color: accent.opacity(b.core), location: 0),
                     .init(color: accent.opacity(b.mid), location: 0.5),
                     .init(color: accent.opacity(0), location: 1)])
        glow(&context, size: size, x: Self.pool.x, y: Self.pool.y, rx: Self.pool.rx, ry: Self.pool.ry,
             stops: fade(Self.pool.strength))
    }

    private func drawStream(_ context: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        drawWake(&context, size: size, t: t)
        drawMotes(&context, size: size, t: t)
    }

    private func fade(_ strength: Double) -> [Gradient.Stop] {
        [.init(color: accent.opacity(strength), location: 0), .init(color: accent.opacity(0), location: 1)]
    }

    /// An elliptical radial glow: a circle of the vertical radius, squeezed across.
    private func glow(_ context: inout GraphicsContext, size: CGSize, x: Double, y: Double, rx: Double, ry: Double,
                      stops: [Gradient.Stop]) {
        let radius = size.height * ry
        guard radius > 0 else { return }
        var squeezed = context
        squeezed.translateBy(x: size.width * x, y: size.height * y)
        squeezed.scaleBy(x: size.width * rx / radius, y: 1)
        squeezed.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: 2 * radius, height: 2 * radius)),
                      with: .radialGradient(Gradient(stops: stops), center: .zero, startRadius: 0, endRadius: radius))
    }

    /// The wake: soft blobs along the stream, faint at its ends, a swell running from the pool to the right.
    private func drawWake(_ context: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let w = Self.wake
        let swellAt = moving ? (t / w.swellPeriod).truncatingRemainder(dividingBy: 1) * 1.4 - 0.2 : 0.45
        for i in 0..<w.blobs {
            let x = Double(i) / Double(w.blobs - 1)
            let ends = sin(.pi * min(max(x * 1.05, 0), 1))
            let swell = exp(-pow((x - swellAt) / w.swell, 2))
            let strength = w.strength * ends * (0.55 + 0.9 * swell)
            glow(&context, size: size, x: x, y: Self.streamY(x, t), rx: w.radius * 2.4 * size.height / size.width,
                 ry: w.radius * (0.8 + 0.4 * ends), stops: fade(strength))
        }
    }

    private func drawMotes(_ context: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        for mote in Self.motes {
            // Along the stream from the pool to the right edge and round again.
            let s = (mote.start + (moving ? t * mote.speed : 0)).truncatingRemainder(dividingBy: 1)
            let x = (0.08 + s * 0.98) * size.width
            let bobT = 2 * .pi * t / mote.bobPeriod + mote.phase
            let px = x + (moving ? cos(bobT) * mote.bob * 0.6 * unit : 0)
            let py = (Self.streamY(s, t) + mote.offset) * size.height + (moving ? sin(bobT) * mote.bob * unit : 0)
            // Fades in leaving the pool and out at the right edge, so nothing pops.
            let life = min(s / 0.12, 1) * min((1 - s) / 0.1, 1)
            let twinkle = moving ? 0.55 + 0.45 * sin(t * mote.twinkle + mote.phase) : 0.8
            let alpha = mote.alpha * life * twinkle
            guard alpha > 0.01 else { continue }
            let r = mote.radius * unit
            let color = mote.inked ? ink : accent
            let rect = CGRect(x: px - r, y: py - r, width: 2 * r, height: 2 * r)
            if mote.soft {
                context.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(stops: [.init(color: color.opacity(alpha), location: 0),
                                     .init(color: color.opacity(alpha * 0.7), location: 0.6),
                                     .init(color: color.opacity(0), location: 1)]),
                    center: CGPoint(x: px, y: py), startRadius: 0, endRadius: r))
            } else {
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
            }
        }
    }
}

/// Deterministic numbers so the particle field is the same every launch.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
