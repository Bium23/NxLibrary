import SwiftUI
import AppKit
import NXLibraryCore

/// A portrait cover in Switch case proportions (Collection, More like this):
/// the player's pick, else the game's real box cover from GameTDB, never a
/// cropped background. Until one
/// is found, or when GameTDB has none, a composed cover: the blurred Title DB
/// banner, the game's icon and its name. The caller applies the corner radius.
struct SwitchBoxArtCover: View {
    let game: PortedGame
    let width: CGFloat
    let height: CGFloat
    /// The official name (Title DB / store), tried after the player's own.
    var officialName: String? = nil
    let boxArt: BoxArtService
    let artwork: ArtworkStore
    /// Bumps when GameTDB's index arrives, so covers that missed look again.
    var indexVersion = 0

    @ObservedObject private var picks = ArtworkPicks.shared
    @State private var cover: NSImage?
    @State private var banner: NSImage?
    @State private var icon: NSImage?

    var body: some View {
        ZStack {
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                composed
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: coverKey) { await loadCover() }
        .task(id: game.id) { await loadComposedArt() }
    }

    // MARK: - Composed cover

    private var composed: some View {
        ZStack {
            SeleneTheme.glassSolid
            if let banner {
                Image(nsImage: banner)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .blur(radius: width * 0.08)
                    .opacity(0.85)
            }
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: height * 0.05) {
                Image(nsImage: icon ?? GameIconProvider.icon(for: game))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width * 0.66, height: width * 0.66)
                    .clipShape(RoundedRectangle(cornerRadius: width * 0.08, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: width * 0.04, y: width * 0.015)
                Text(officialName ?? game.name)
                    .font(.system(size: width * 0.085, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, width * 0.08)
            }
            .padding(.top, height * 0.04)
        }
    }

    // MARK: - Loading

    private var names: [String] {
        [game.name] + (officialName.map { [$0] } ?? [])
    }

    private var titleID: String { game.titleId ?? game.uniqueKey }

    private var coverKey: String { "\(game.id)|\(officialName ?? "")|\(indexVersion)|\(picks.revision)" }

    private func loadCover() async {
        let key = "box|\(game.id)|\(picks.revision)" as NSString
        if let memo = CoverArtMemo.shared.object(forKey: key) {
            cover = memo
            return
        }
        var url = picks.url(titleID: titleID, slot: .cover)
        if url == nil { url = await boxArt.boxArt(titleID: titleID, names: names) }
        guard !Task.isCancelled else { return }
        // No cover (a pick taken back, GameTDB without one): the composed cover shows.
        guard let url, let image = await GameArtLoader.decode(at: url, maxPixelSize: 900) else {
            cover = nil
            return
        }
        guard !Task.isCancelled else { return }
        CoverArtMemo.shared.setObject(image, forKey: key)
        withAnimation(.easeInOut(duration: 0.2)) { cover = image }
    }

    /// The banner and Title DB icon for the composed cover (both cached on disk).
    private func loadComposedArt() async {
        if let own = GameIconProvider.squareArt(for: game) {
            icon = own
        } else if let titleId = game.titleId,
                  let url = await artwork.automaticIcon(titleID: titleId, name: game.name) {
            icon = await GameArtLoader.decode(at: url, maxPixelSize: 512)
        }
        guard !Task.isCancelled, game.titleId != nil else { return }
        if let url = await artwork.fetch(titleID: titleID, remoteURL: nil, kind: .hero) {
            banner = await GameArtLoader.decode(at: url, maxPixelSize: 640)
        }
    }
}

/// Decoded box covers, so a cover that scrolls back into the row paints at once.
private enum CoverArtMemo {
    static let shared: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()
}
