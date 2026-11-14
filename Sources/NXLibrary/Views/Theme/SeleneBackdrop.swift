import SwiftUI
import AppKit
import NXLibraryCore

/// What the backdrop draws, set once on the shell from settings.
struct SeleneBackdropStyle: Equatable {
    var wallpaperURL: URL?
    var sizing: BackgroundSizing = .fill
    var animated = true
    var brightness: WallpaperBrightness = .balanced
}

extension WallpaperBrightness {
    /// A left-to-right mask carrying the setting's opacity, for a wallpaper or a video.
    var mask: LinearGradient {
        LinearGradient(stops: stops.map { .init(color: .black.opacity($0.opacity), location: $0.location) },
                       startPoint: .leading, endPoint: .trailing)
    }
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

    /// The base gradient's opacity; the wallpaper's follows Wallpaper brightness.
    var baseOpacity = 0.6
    /// Covered (a game's art over it): the moonlight or the video holds still and costs nothing.
    var still = false

    /// The Mods card: the moonlight turns gold (over a wallpaper too), gliding there and back.
    var modsTint = false

    /// The Mods card's colours, whatever the palette.
    static let modsAccent = Color(hex: 0xFFC94A)
    static let modsGradient = LinearGradient(stops: [
        .init(color: Color(hex: 0x8A5A0E), location: 0),
        .init(color: Color(hex: 0x3A2508), location: 0.45),
        .init(color: Color(hex: 0x05080F), location: 1)
    ], startPoint: .top, endPoint: .bottom)
    /// The tint's glide, the same length as the moonlight's colour glide.
    static let tintGlide = Animation.easeInOut(duration: 1.2)

    func modsTint(_ on: Bool) -> SeleneBackdrop {
        var copy = self
        copy.modsTint = on
        return copy
    }

    func still(_ on: Bool) -> SeleneBackdrop {
        var copy = self
        copy.still = on
        return copy
    }

    var body: some View {
        let moving = style.animated && !reduceMotion && !still
        let hasWallpaper = style.wallpaperURL != nil
        return ZStack {
            SeleneTheme.scrim
            Rectangle().fill(SeleneTheme.baseGradient).opacity(baseOpacity)
            if MoonlightEngine.shared == nil {
                // Without Metal the tint is a layer of its own; with it the moonlight's shader draws the ground,
                // in step with its light and off the main thread.
                modsGround.opacity(modsTint ? 1 : 0)
            }
            if let url = style.wallpaperURL, WallpaperCatalog.kind(of: url) == .video {
                // Under the Mods card's moonlight the video holds still and costs nothing.
                LiveBackdrop(url: url, playing: moving && !modsTint, sizing: style.sizing)
                    .mask(style.brightness.mask)
            } else if let url = style.wallpaperURL, let image = WallpaperImageCache.shared.image(at: url) {
                wallpaper(image)
                    .mask(style.brightness.mask)
            } else {
                MoonlightBackdrop(accent: modsTint ? Self.modsAccent : SeleneTheme.glyph, ink: SeleneTheme.ink,
                                  tint: modsTint ? 1 : 0, moving: moving)
            }
            if hasWallpaper, MoonlightEngine.shared != nil {
                // Over a wallpaper the Mods card brings its own moonlight. It stays mounted (hidden and idle while
                // gone) and glides in and out on its render thread, so a quick there-and-back carries on from
                // where it is, and the motes never start over.
                MoonlightBackdrop(accent: Self.modsAccent, ink: SeleneTheme.ink, tint: 1,
                                  presence: modsTint ? 1 : 0, moving: moving)
            } else if modsTint, hasWallpaper {
                ZStack {
                    modsGround
                    MoonlightBackdrop(accent: Self.modsAccent, ink: SeleneTheme.ink, tint: 1, moving: moving)
                }
                .transition(.opacity)
            }
        }
        .animation(Self.tintGlide, value: modsTint)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The Mods card's ground, the base it replaces (its own scrim, so no blue shows through and greys it).
    private var modsGround: some View {
        ZStack {
            SeleneTheme.scrim
            Rectangle().fill(Self.modsGradient).opacity(baseOpacity)
        }
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
/// (`MoonlightEngine`, `MoonlightShaders`; the field is `MoonlightField`), 60 fps
/// or one still frame. Without Metal, the beam and pool hold still in SwiftUI.
struct MoonlightBackdrop: View {
    let accent: Color
    let ink: Color
    /// The Mods card's gold ground drawn under the light (0...1).
    var tint: Float = 0
    /// The whole layer's opacity (0...1), gliding.
    var presence: Float = 1
    var moving = true
    /// A still image instead of a live layer: for small cards that clip and round it.
    var asImage = false

    var body: some View {
        let colors = MoonlightColors(accent: accent, ink: ink, tint: tint, presence: presence)
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
