import SwiftUI
import AppKit
import NXLibraryCore

/// Square tile art: the player's pick first. Then, with `ownIconFirst`, the
/// game's own icon art (the built app's icon, as on the Mac), so every tile is
/// the same full-bleed square.
/// Otherwise (or without one): Title DB's 1024 icon by title ID, then the
/// generic icon. Crossfades when fetched art arrives.
/// The caller applies the corner radius.
struct SpotlightTileArtwork: View {
    let game: PortedGame
    /// Side length in points, already scaled by the caller.
    let side: CGFloat
    /// The app's shared artwork cache.
    let artwork: ArtworkStore
    /// Show the game's own icon art (as on the Mac) whenever it exists (Spotlight's row).
    var ownIconFirst = false

    @ObservedObject private var picks = ArtworkPicks.shared
    @State private var better: NSImage?
    @State private var picked: NSImage?

    var body: some View {
        ZStack {
            SeleneTheme.glassSolid
            if let picked {
                Image(nsImage: picked)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else if ownIconFirst, let own = GameIconProvider.squareArt(for: game) {
                Image(nsImage: own)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else if let better {
                Image(nsImage: better)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(nsImage: GameIconProvider.icon(for: game))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .task(id: "\(game.id)|\(picks.revision)") {
            if let url = picks.url(titleID: game.titleId ?? game.uniqueKey, slot: .icon) {
                picked = await GameArtLoader.decode(at: url, maxPixelSize: 512)
                return
            }
            picked = nil
            guard !ownIconFirst || GameIconProvider.squareArt(for: game) == nil else { return }
            let key = game.id.uuidString as NSString
            if let memo = TileArtMemo.shared.object(forKey: key) {
                better = memo
                return
            }
            let loaded = await loadIcon()
            guard !Task.isCancelled, let loaded else { return }
            TileArtMemo.shared.setObject(loaded, forKey: key)
            withAnimation(.easeInOut(duration: 0.2)) { better = loaded }
        }
    }

    private func loadIcon() async -> NSImage? {
        guard let titleID = game.titleId, !titleID.isEmpty else { return nil }
        var url = artwork.cachedURL(titleID: titleID, kind: .square)
        if url == nil {
            url = await artwork.fetch(titleID: titleID, remoteURL: URL(string: "https://api.nlib.cc/nx/\(titleID)/icon"),
                                      kind: .square)
        }
        guard let url else { return nil }
        return await GameArtLoader.decode(at: url, maxPixelSize: 512)
    }
}

/// Decoded tile art, so a tile that scrolls back into the row paints at once.
private enum TileArtMemo {
    static let shared: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()
}
