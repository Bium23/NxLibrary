import SwiftUI
import AppKit
import NXLibraryCore

/// Square tile art for the Spotlight row: SteamGridDB square grid, then the
/// Nintendo store cover, then the app icon. Shows the icon immediately and
/// crossfades when better art arrives. The caller applies the corner radius.
struct SpotlightTileArtwork: View {
    let game: PortedGame
    /// Side length in points, already scaled by the caller.
    let side: CGFloat
    /// SteamGridDB key; empty means no SteamGridDB request is made.
    var steamGridDbApiKey: String = ""

    @State private var better: NSImage?

    var body: some View {
        ZStack {
            Image(nsImage: GameIconProvider.icon(for: game))
                .resizable()
                .aspectRatio(contentMode: .fill)
            if let better {
                Image(nsImage: better)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .task(id: game.id) {
            better = nil
            let loaded = await Self.loadBest(for: game, apiKey: steamGridDbApiKey)
            guard !Task.isCancelled, let loaded else { return }
            withAnimation(.easeInOut(duration: 0.2)) { better = loaded }
        }
    }

    private static func loadBest(for game: PortedGame, apiKey: String) async -> NSImage? {
        let titleID = game.titleId ?? game.uniqueKey
        let store = ArtworkStore()

        var squareURL = store.cachedURL(titleID: titleID, kind: .square)
        if squareURL == nil {
            squareURL = await fetchSquare(store: store, titleID: titleID, game: game, apiKey: apiKey)
        }
        if let squareURL, let image = await decode(squareURL) { return image }
        if let url = store.cachedURL(titleID: titleID, kind: .cover) {
            return await decode(url)
        }
        if let remote = NintendoStoreMetadataService().cached(for: titleID)?.imageURL,
           let url = await store.fetch(titleID: titleID, remoteURL: remote, kind: .cover) {
            return await decode(url)
        }
        return nil
    }

    private static func fetchSquare(store: ArtworkStore, titleID: String,
                                    game: PortedGame, apiKey: String) async -> URL? {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let remote = await SteamGridDBService()
            .fetchSquareGridURL(gameName: game.name, apiKey: apiKey) else { return nil }
        return await store.fetch(titleID: titleID, remoteURL: remote, kind: .square)
    }

    private static func decode(_ url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
    }
}
