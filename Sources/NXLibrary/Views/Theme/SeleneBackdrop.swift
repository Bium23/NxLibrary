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

/// Selene's base layer (Main.xaml): scrim, the palette's base gradient, the wallpaper at 0.6,
/// and, when on and motion is allowed, a slow light beam with drifting particles.
struct SeleneBackdrop: View {
    @Environment(\.seleneBackdropStyle) private var style
    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SeleneTheme.scrim
            Rectangle().fill(SeleneTheme.baseGradient).opacity(0.6)
            if let url = style.wallpaperURL, let image = WallpaperImageCache.shared.image(at: url) {
                wallpaper(image)
                    .opacity(0.6)
            }
            if style.animated && !reduceMotion {
                SeleneAmbientMotion()
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

/// A diagonal beam sweeping over 24 s and ~40 dots drifting upward, drawn at 30 fps.
private struct SeleneAmbientMotion: View {
    @Environment(\.seleneCanvas) private var canvas

    private struct Particle {
        let x: Double
        let y: Double
        let radius: Double
        let alpha: Double
        let speed: Double
    }

    private static let particles: [Particle] = {
        var generator = SplitMix(seed: 0x5E1E4E)
        return (0..<40).map { _ in
            Particle(x: generator.unit(), y: generator.unit(),
                     radius: 1 + generator.unit() * 2,
                     alpha: 0.08 + generator.unit() * 0.17,
                     speed: 4 + generator.unit() * 6)
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                drawBeam(&context, size: size, t: t)
                drawParticles(&context, size: size, t: t)
            }
        }
    }

    private func drawBeam(_ context: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let phase = (t.truncatingRemainder(dividingBy: 24)) / 24
        let width = size.width * 0.35
        let x = -width + (size.width + 2 * width) * phase
        let ink = SeleneTheme.ink
        var beam = Path()
        beam.addRect(CGRect(x: x, y: -size.height * 0.2, width: width, height: size.height * 1.4))
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [.init(color: ink.opacity(0), location: 0),
                             .init(color: ink.opacity(0.06), location: 0.5),
                             .init(color: ink.opacity(0), location: 1)]),
            startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x + width, y: 0))
        var rotated = context
        rotated.translateBy(x: size.width / 2, y: size.height / 2)
        rotated.rotate(by: .degrees(18))
        rotated.translateBy(x: -size.width / 2, y: -size.height / 2)
        rotated.fill(beam, with: shading)
    }

    private func drawParticles(_ context: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let ink = SeleneTheme.ink
        let span = size.height + 20
        for p in Self.particles {
            let travelled = (t * canvas.u(p.speed)).truncatingRemainder(dividingBy: span)
            var y = p.y * span - travelled
            if y < -10 { y += span }
            let r = canvas.u(p.radius)
            let rect = CGRect(x: p.x * size.width - r, y: y - r, width: 2 * r, height: 2 * r)
            context.fill(Path(ellipseIn: rect), with: .color(ink.opacity(p.alpha)))
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
