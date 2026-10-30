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
/// wallpaper, still or live (a looping video, `LiveBackdrop`, which follows the
/// moonlight's rule for moving). Without a wallpaper the theme's own backdrop shows (Selene's
/// moonlight, `MoonlightBackdrop`): moving when on and motion is allowed, still otherwise.
struct SeleneBackdrop: View {
    @Environment(\.seleneBackdropStyle) private var style
    @Environment(\.seleneReduceMotion) private var reduceMotion

    /// The base gradient's and the wallpaper's opacity.
    var baseOpacity = 0.6
    var wallpaperOpacity = 0.6
    /// Covered (a game's art over it): the moonlight or the video holds still and costs nothing.
    var still = false

    func still(_ on: Bool) -> SeleneBackdrop {
        var copy = self
        copy.still = on
        return copy
    }

    var body: some View {
        ZStack {
            SeleneTheme.scrim
            Rectangle().fill(SeleneTheme.baseGradient).opacity(baseOpacity)
            if let url = style.wallpaperURL, WallpaperCatalog.kind(of: url) == .video {
                LiveBackdrop(url: url, playing: style.animated && !reduceMotion && !still, sizing: style.sizing)
                    .opacity(wallpaperOpacity)
            } else if let url = style.wallpaperURL, let image = WallpaperImageCache.shared.image(at: url) {
                wallpaper(image)
                    .opacity(wallpaperOpacity)
            } else {
                MoonlightBackdrop(accent: SeleneTheme.glyph, ink: SeleneTheme.ink,
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

/// The theme's own backdrop, after Selene's looping video: a smoky beam of the
/// theme's accent falling from the top left onto a pool of light on the floor,
/// breathing; from the pool a band of thousands of motes rises to the right, far
/// ones fine and sharp, near ones blurred into bokeh. Drawn by Metal
/// (`MoonlightEngine`, `MoonlightShaders`; the field is `MoonlightField`), 30 fps
/// or one still frame. Without Metal, the beam and pool hold still in SwiftUI.
struct MoonlightBackdrop: View {
    let accent: Color
    let ink: Color
    var moving = true
    /// A still image instead of a live layer: for small cards that clip and round it.
    var asImage = false

    var body: some View {
        let colors = MoonlightColors(accent: accent, ink: ink)
        if let engine = MoonlightEngine.shared {
            if asImage {
                MoonlightStill(engine: engine, colors: colors)
            } else {
                MoonlightMetalView(engine: engine, colors: colors, moving: moving)
            }
        } else {
            Canvas { context, size in
                glow(&context, size: size, x: 0.17, y: -0.06, rx: 0.13, ry: 0.55, strength: 0.4)
                glow(&context, size: size, x: 0.2, y: 0.86, rx: 0.2, ry: 0.07, strength: 0.3)
            }
        }
    }

    /// An elliptical radial glow: a circle of the vertical radius, squeezed across.
    private func glow(_ context: inout GraphicsContext, size: CGSize, x: Double, y: Double, rx: Double, ry: Double,
                      strength: Double) {
        let radius = size.height * ry
        guard radius > 0 else { return }
        var squeezed = context
        squeezed.translateBy(x: size.width * x, y: size.height * y)
        squeezed.scaleBy(x: size.width * rx / radius, y: 1)
        squeezed.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: 2 * radius, height: 2 * radius)),
                      with: .radialGradient(Gradient(colors: [accent.opacity(strength), accent.opacity(0)]),
                                            center: .zero, startRadius: 0, endRadius: radius))
    }
}
