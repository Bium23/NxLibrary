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
            let personal = picks
            let picked = remote == nil ? personal.url(titleID: game.personalizationReference.key, slot: slot) : nil
            let url: URL?
            if let picked { url = picked }
            else { url = await SteamMetadataService.shared.image(appID: id, slot: slot, remote: remote) }
            guard !Task.isCancelled else { return }
            image = url.flatMap { NSImage(contentsOf: $0) }; loadedKey = expected
        }

        .accessibilityLabel(game.name)
    }
}

extension Notification.Name { static let steamPersonalizationChanged = Notification.Name("NXSteamPersonalizationChanged") }

struct SteamBackdrop: View {
    let game: CatalogGame
    let shade: BackgroundShade
    let showsArt: Bool
    var body: some View {
        Group { if showsArt { SteamArtwork(game: game, slot: .background)
            .overlay(SeleneShades(shade: shade)) } }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
