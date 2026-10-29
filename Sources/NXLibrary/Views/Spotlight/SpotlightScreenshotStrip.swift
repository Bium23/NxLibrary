import SwiftUI
import AppKit
import NXLibraryCore

/// The selected game's screenshots (Main.xaml HubBottomCards): up to six tiles
/// 448 × 252, radius 14, gap 22, on glassSolid; the focused one gets a 3u ring
/// 4 outside it (radius 17) and grows 1.03. The strip's clip is 1788 wide and
/// starts 14 left of the first tile so the first ring is not cut.
struct SpotlightScreenshotStrip: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    static let maxCount = 6

    let titleID: String
    let urls: [URL]
    /// False while the game's metadata is still loading (no "none" message yet).
    let known: Bool
    let focusedIndex: Int?
    let artwork: ArtworkStore
    let onSelect: (Int) -> Void

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
            HStack(spacing: canvas.u(22)) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, url in
                    ScreenshotTile(titleID: titleID, index: index, url: url,
                                   focused: focusedIndex == index, artwork: artwork)
                        .onTapGesture { onSelect(index) }
                }
            }
            .padding(canvas.u(14))
            .offset(x: -canvas.u(scroll))
            .frame(width: canvas.u(1788), alignment: .leading)
            .clipped()
            .padding(canvas.u(-14))
            .animation(reduceMotion ? nil : SeleneTheme.cubicOut(0.25), value: focusedIndex)
        }
    }

    /// Keeps the focused tile (and its ring) inside the 1788 clip.
    private var scroll: CGFloat {
        guard let focusedIndex else { return 0 }
        let right = CGFloat(focusedIndex) * (448 + 22) + 448 + 14 + 14
        return max(0, right - 1788)
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

    @State private var image: NSImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
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
        .frame(width: canvas.u(448), height: canvas.u(252))
        .overlay(
            RoundedRectangle(cornerRadius: canvas.u(17), style: .continuous)
                .strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(3))
                .padding(canvas.u(-4))
                .opacity(focused ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: focused)
        )
        .scaleEffect(focused ? 1.03 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: focused)
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
