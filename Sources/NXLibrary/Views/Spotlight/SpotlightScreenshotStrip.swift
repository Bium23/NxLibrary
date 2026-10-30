import SwiftUI
import AppKit
import NXLibraryCore

/// The selected game's screenshots (Main.xaml HubBottomCards): up to six tiles
/// on glassSolid, the focused one with a 3u ring 4 outside it and a grow. The
/// default `Style` is Spotlight's (448 × 252, radius 14, gap 22, grow 1.03);
/// Details passes its own. The strip's clip is 1788 wide and starts 14 left of
/// the first tile so the first ring is not cut.
struct SpotlightScreenshotStrip: View {
    /// Tile geometry in Selene units. The ring sits 4 outside the tile, 3 thick,
    /// at the tile's radius + 3.
    struct Style: Equatable {
        var tileWidth: CGFloat = 448
        var tileHeight: CGFloat = 252
        var radius: CGFloat = 14
        var gap: CGFloat = 22
        var focusScale: CGFloat = 1.03

        /// Spotlight's strip.
        static let spotlight = Style()
        /// Selene DetailsStage's band tiles: 272 × 153, radius 12, gap 20, grow 1.05.
        static let details = Style(tileWidth: 272, tileHeight: 153, radius: 12, gap: 20, focusScale: 1.05)
    }

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    static let maxCount = 6
    /// The clip the strip scrolls within (Selene units).
    private static let clipWidth: CGFloat = 1788

    let titleID: String
    let urls: [URL]
    /// False while the game's metadata is still loading (no "none" message yet).
    let known: Bool
    let focusedIndex: Int?
    let artwork: ArtworkStore
    let onSelect: (Int) -> Void
    /// When set, a single click only focuses (`onSelect`) and a double click opens (`onActivate`).
    var onActivate: ((Int) -> Void)? = nil
    var style: Style = .spotlight

    private var shown: [URL] { Array(urls.prefix(Self.maxCount)) }

    var body: some View {
        if shown.isEmpty {
            if known {
                Text("No screenshots for this game")
                    .seleneFont(18)
                    .foregroundColor(SeleneTheme.ink60)
                    .shadow(color: .black.opacity(0.45), radius: canvas.u(4))
            }
        } else {
            HStack(spacing: canvas.u(style.gap)) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, url in
                    let tile = ScreenshotTile(titleID: titleID, index: index, url: url,
                                              focused: focusedIndex == index, artwork: artwork,
                                              style: style)
                    if let onActivate {
                        tile
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { onActivate(index) }
                            .simultaneousGesture(TapGesture().onEnded { onSelect(index) })
                    } else {
                        tile.onTapGesture { onSelect(index) }
                    }
                }
            }
            .padding(canvas.u(14))
            .offset(x: -canvas.u(scroll))
            .frame(width: canvas.u(Self.clipWidth), alignment: .leading)
            .clipped()
            .padding(canvas.u(-14))
            .animation(reduceMotion ? nil : Self.motion, value: focusedIndex)
        }
    }

    /// One curve for the slide, the grow and the ring, so a tile entering at the
    /// edge does not grow on a faster clock than the strip moves (which shimmered).
    static let motion = SeleneTheme.cubicOut(0.25)

    /// Keeps the focused tile (and its ring) inside the clip.
    private var scroll: CGFloat {
        guard let focusedIndex else { return 0 }
        let right = CGFloat(focusedIndex) * (style.tileWidth + style.gap) + style.tileWidth + 14 + 14
        return max(0, right - Self.clipWidth)
    }
}

private struct ScreenshotTile: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let titleID: String
    let index: Int
    let url: URL
    let focused: Bool
    let artwork: ArtworkStore
    let style: SpotlightScreenshotStrip.Style

    @State private var image: NSImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(style.radius), style: .continuous)
        ZStack {
            shape.fill(SeleneTheme.glassSolid)
            if let image {
                Color.clear
                    .overlay(Image(nsImage: image).resizable().interpolation(.high)
                        .aspectRatio(contentMode: .fill))
                    .clipShape(shape)
                    .transition(.opacity)
            }
        }
        .frame(width: canvas.u(style.tileWidth), height: canvas.u(style.tileHeight))
        // Rasterised once and moved as one layer: the detailed screenshot does not
        // resample its edges every frame of the slide.
        .drawingGroup()
        .overlay(
            RoundedRectangle(cornerRadius: canvas.u(style.radius + 3), style: .continuous)
                .strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(3))
                .padding(canvas.u(-4))
                .opacity(focused ? 1 : 0)
        )
        .scaleEffect(focused ? style.focusScale : 1)
        .animation(reduceMotion ? nil : SpotlightScreenshotStrip.motion, value: focused)
        .accessibilityElement()
        .accessibilityLabel("Screenshot \(index + 1)")
        .task(id: "\(titleID)|\(index)|\(url.absoluteString)") {
            image = nil
            guard let file = await artwork.screenshot(titleID: titleID, index: index, remoteURL: url),
                  let decoded = await GameArtLoader.decode(at: file, maxPixelSize: 1000),
                  !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { image = decoded }
        }
    }
}
