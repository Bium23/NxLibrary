import SwiftUI
import AppKit
import NXLibraryCore

/// Same source-qualified personal picks as metadata; downloaded art never writes
/// into Steam or its app bundles. Task identity includes locale-independent URL.
struct SteamArtwork: View {
    let game: CatalogGame
    let slot: ArtworkSlot
    var remote: URL? = nil
    @State private var image: NSImage?
    @State private var loadedKey = ""
    @Environment(\.seleneCanvas) private var canvas
    @ObservedObject private var picks = SteamPersonalizations.shared.artwork
    private var key: String { "\(game.id)|\(slot.rawValue)|\(remote?.absoluteString ?? "")|\(picks.revision)" }
    private var role: LibraryArtworkRole { LibraryArtworkRole.allCases.first { $0.slot == slot } ?? .hero }
    var body: some View {
        ZStack {
            if let image, loadedKey == key {
                Image(nsImage: image).resizable().aspectRatio(contentMode: slot == .logo ? .fit : .fill)
            } else if slot == .cover || slot == .icon {
                if let app = game.steamGame?.installations.first(where: { $0.availability == .available })?.primaryApplication {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().scaledToFit().padding(canvas.u(16))
                } else { Image(systemName: "gamecontroller.fill").resizable().scaledToFit().padding(canvas.u(30)) }
            } else { Color.clear }
        }
        .clipped()
        .task(id: key) {
            let expected = key
            guard let id = game.steamGame?.appID else { return }
            let request = SteamArtworkRequest(game: game, role: role)
            let url: URL?
            if remote == nil, let local = request.localURL(picks: picks) { url = local }
            // A square never falls back to store art: that would be a cropped portrait cover.
            else if role == .square { url = nil }
            else { url = await SteamMetadataService.shared.image(appID: id, slot: slot, remote: remote) }
            guard !Task.isCancelled else { return }
            // Decoded off the main thread at the size its nxnative twin uses: a lazily decoded file cost the
            // first frame that drew it 40–60 ms.
            let decoded: NSImage? = if let url { await GameArtLoader.decode(at: url, maxPixelSize: slot.decodedSize) } else { nil }
            guard !Task.isCancelled else { return }
            image = decoded; loadedKey = expected
        }

        .accessibilityLabel(game.name)
    }
}

private extension ArtworkSlot {
    /// The nxnative sizes: tiles' icons 512 px (`SpotlightTileArtwork`), box covers 900 (`SwitchBoxArtCover`),
    /// logos and heroes as `GameArtLoader`.
    var decodedSize: Int {
        switch self {
        case .icon: return 512
        case .cover: return 900
        case .logo: return 1600
        case .background: return 2560
        }
    }
}
