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
/// wallpaper at 0.6. Without a wallpaper the theme's own backdrop shows (Selene's
/// moonlight, `MoonlightBackdrop`): moving when on and motion is allowed, still otherwise.
struct SeleneBackdrop: View {
    @Environment(\.seleneBackdropStyle) private var style
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        ZStack {
            SeleneTheme.scrim
            Rectangle().fill(SeleneTheme.baseGradient).opacity(0.6)
            if let url = style.wallpaperURL, let image = WallpaperImageCache.shared.image(at: url) {
                wallpaper(image)
                    .opacity(0.6)
            } else {
                MoonlightBackdrop(accent: SeleneTheme.glyph, ink: SeleneTheme.ink, unit: canvas.u(1),
                                  moving: style.animated && !reduceMotion)
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

/// The theme's own backdrop, drawn after Selene's moving one (its looping video
/// and LoginScene's glow): a beam of the theme's accent falling from the top
/// left and slowly breathing, a wider wash around it, a haze on the floor, and a
/// band of motes rising to the right, far ones fine and sharp, near ones large
/// and soft, drifting right with a little sway and twinkle. Every look is a
/// number below, in the theme's colors; 30 fps, or one still frame.
struct MoonlightBackdrop: View {
    let accent: Color
    let ink: Color
    /// One Selene unit in points (the canvas's), so a small preview scales down.
    let unit: CGFloat
    var moving = true

    // MARK: Look

    /// Beam: centre and radii as fractions of the window, strength at its heart and half way, breath period (s).
    static let beam = (x: 0.14, y: -0.08, rx: 0.2, ry: 0.85, core: 0.42, mid: 0.14, breath: 9.0)
    /// Wash around the beam, and the floor's haze (centre, radii, strength).
    static let wash = (x: 0.16, y: -0.12, rx: 0.6, ry: 1.1, strength: 0.16)
    static let haze = (x: 0.5, y: 1.02, rx: 0.95, ry: 0.34, strength: 0.22)
    /// The motes' band: its height at the left and right edges, and its spread.
    static let band = (left: 0.86, right: 0.46, spread: 0.11)

    struct Layer {
        let count: Int
        /// Radius in Selene units, opacity, speed (units per second, rightwards).
        let radius: ClosedRange<Double>
        let alpha: ClosedRange<Double>
        let speed: ClosedRange<Double>
        /// Soft discs (bokeh) instead of sharp points.
        let soft: Bool
        /// Scattered over the whole window instead of along the band.
        let scattered: Bool
    }

    static let layers = [
        Layer(count: 110, radius: 0.5...1.3, alpha: 0.25...0.7, speed: 2...5, soft: false, scattered: false),
        Layer(count: 30, radius: 1.6...3.0, alpha: 0.25...0.5, speed: 5...9, soft: true, scattered: false),
        Layer(count: 10, radius: 5...11, alpha: 0.1...0.22, speed: 8...14, soft: true, scattered: true)
    ]
    /// Of every mote, the share drawn in the ink (white-ish) rather than the accent.
    static let inkShare = 0.2

    // MARK: Drawing

    private struct Mote {
        let x, y, radius, alpha, speed, sway, phase, twinkle: Double
        let soft, inked: Bool
    }

    private static let motes: [Mote] = {
        var random = SplitMix(seed: 0x5E1E4E)
        var motes: [Mote] = []
        for layer in layers {
            for _ in 0..<layer.count {
                let x = random.unit()
                let y: Double
                if layer.scattered {
                    y = 0.1 + random.unit() * 0.85
                } else {
                    // Box-Muller: most motes near the band's line, a few further out.
                    let gauss = (-2 * log(max(random.unit(), 1e-9))).squareRoot() * cos(2 * .pi * random.unit())
                    y = band.left + (band.right - band.left) * x + gauss * band.spread
                }
                func pick(_ range: ClosedRange<Double>) -> Double {
                    range.lowerBound + (range.upperBound - range.lowerBound) * random.unit()
                }
                motes.append(Mote(x: x, y: y, radius: pick(layer.radius), alpha: pick(layer.alpha),
                                  speed: pick(layer.speed), sway: 2 + random.unit() * 4,
                                  phase: random.unit() * 2 * .pi, twinkle: 0.9 + random.unit() * 1.2,
                                  soft: layer.soft, inked: random.unit() < inkShare))
            }
        }
        return motes
    }()

    var body: some View {
        if moving {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                Canvas { context, size in
                    draw(&context, size: size, t: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        } else {
            Canvas { context, size in draw(&context, size: size, t: 0) }
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let b = Self.beam
        glow(&context, size: size, x: Self.wash.x, y: Self.wash.y, rx: Self.wash.rx, ry: Self.wash.ry,
             stops: [.init(color: accent.opacity(Self.wash.strength), location: 0),
                     .init(color: accent.opacity(0), location: 1)])
        var beam = context
        beam.opacity = moving ? 0.875 + 0.125 * sin(2 * .pi * t / b.breath) : 1
        glow(&beam, size: size, x: b.x, y: b.y, rx: b.rx, ry: b.ry,
             stops: [.init(color: accent.opacity(b.core), location: 0),
                     .init(color: accent.opacity(b.mid), location: 0.5),
                     .init(color: accent.opacity(0), location: 1)])
        glow(&context, size: size, x: Self.haze.x, y: Self.haze.y, rx: Self.haze.rx, ry: Self.haze.ry,
             stops: [.init(color: accent.opacity(Self.haze.strength), location: 0),
                     .init(color: accent.opacity(0), location: 1)])
        drawMotes(&context, size: size, t: t)
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

    private func drawMotes(_ context: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let margin = 24 * unit
        let span = size.width + 2 * margin
        for mote in Self.motes {
            let travelled = (t * mote.speed * unit).truncatingRemainder(dividingBy: span)
            var x = mote.x * span + travelled
            if x > span { x -= span }
            x -= margin
            let y = mote.y * size.height + sin(t * 0.2 + mote.phase) * mote.sway * unit
            let r = mote.radius * unit
            let alpha = mote.alpha * (moving ? 0.65 + 0.35 * sin(t * mote.twinkle + mote.phase) : 0.85)
            let color = mote.inked ? ink : accent
            let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            if mote.soft {
                context.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(stops: [.init(color: color.opacity(alpha), location: 0),
                                     .init(color: color.opacity(alpha * 0.6), location: 0.55),
                                     .init(color: color.opacity(0), location: 1)]),
                    center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
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
