import SwiftUI
import AppKit
import NXLibraryCore

/// Tile art: SteamGridDB square grid, then the Nintendo store cover, then the
/// app icon (Spotlight's row); with `coverFirst` the store cover, then the
/// square art, then the app icon (Collection's covers). Shows the icon
/// immediately and crossfades when better art arrives. The caller applies the
/// corner radius.
struct SpotlightTileArtwork: View {
    let game: PortedGame
    /// Side length (height) in points, already scaled by the caller.
    let side: CGFloat
    /// Width in points when the tile is not square (Collection's portrait covers).
    var width: CGFloat? = nil
    /// Prefer the store cover over the square art.
    var coverFirst = false
    /// SteamGridDB key; empty means no SteamGridDB request is made.
    var steamGridDbApiKey: String = ""
    /// The app's shared artwork cache and SteamGridDB client.
    let artwork: ArtworkStore
    let steamGridDB: SteamGridDBService
    /// The store's cover (`NintendoStoreMetadata.imageURL`), when known.
    var coverURL: URL? = nil

    @State private var better: NSImage?

    var body: some View {
        ZStack {
            SeleneTheme.glassSolid
            if let better {
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
        .frame(width: width ?? side, height: side)
        .clipped()
        .task(id: memoKey) {
            let key = memoKey as NSString
            if let memo = TileArtMemo.shared.object(forKey: key) {
                better = memo
                return
            }
            let loaded = await loadBest()
            guard !Task.isCancelled, let loaded else { return }
            TileArtMemo.shared.setObject(loaded, forKey: key)
            withAnimation(.easeInOut(duration: 0.2)) { better = loaded }
        }
    }

    private var memoKey: String {
        "\(game.id)|\(coverURL?.absoluteString ?? "")|\(steamGridDbApiKey)|\(coverFirst)"
    }

    private func loadBest() async -> NSImage? {
        let titleID = game.titleId ?? game.uniqueKey
        if coverFirst {
            if let image = await loadCover(titleID: titleID) { return image }
            return await loadSquare(titleID: titleID)
        }
        if let image = await loadSquare(titleID: titleID) { return image }
        return await loadCover(titleID: titleID)
    }

    private func loadSquare(titleID: String) async -> NSImage? {
        var squareURL = artwork.cachedURL(titleID: titleID, kind: .square)
        if squareURL == nil {
            squareURL = await fetchSquare(titleID: titleID)
        }
        guard let squareURL else { return nil }
        return await GameArtLoader.decode(at: squareURL, maxPixelSize: 512)
    }

    private func loadCover(titleID: String) async -> NSImage? {
        if let url = artwork.cachedURL(titleID: titleID, kind: .cover) {
            return await GameArtLoader.decode(at: url, maxPixelSize: 512)
        }
        if let coverURL, let url = await artwork.fetch(titleID: titleID, remoteURL: coverURL, kind: .cover) {
            return await GameArtLoader.decode(at: url, maxPixelSize: 512)
        }
        return nil
    }

    private func fetchSquare(titleID: String) async -> URL? {
        let apiKey = steamGridDbApiKey
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard !SquareGridMemo.shared.contains(game.id, apiKey: apiKey) else { return nil }
        let result = await steamGridDB.lookupSquareGrid(gameName: game.name, apiKey: apiKey)
        SquareGridMemo.shared.record(result, cancelled: Task.isCancelled,
                                     id: game.id, apiKey: apiKey)
        guard case .found(let remote) = result else { return nil }
        return await artwork.fetch(titleID: titleID, remoteURL: remote, kind: .square)
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
