import SwiftUI
import AppKit
import NXLibraryCore

/// Native-app artwork for non-nxnative entries. It never asks Nintendo artwork
/// services or writes the installed app. Existing nxnative art keeps its path.
struct CatalogNativeArtwork: View {
    let game: CatalogGame
    @Environment(\.seleneCanvas) private var canvas
    @State private var image: NSImage?
    private var application: CatalogNativeApplication? {
        game.steamGame?.installations.first { $0.availability == .available }?.primaryApplication
    }
    private var key: String { (application?.url.path ?? "none") + "|" + (game.steamGame?.installations.first?.buildID ?? "") }
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SeleneTheme.glassSolid
            SteamArtwork(game: game, slot: .cover)
            Text("Steam").seleneFont(12, .semibold).foregroundColor(SeleneTheme.ink)
                .padding(.horizontal, canvas.u(8)).padding(.vertical, canvas.u(4))
                .background(Capsule().fill(SeleneTheme.glassSolid)).padding(canvas.u(9))
        }
        .task(id: key) {
            guard !Task.isCancelled else { return }
            image = application.map { NSWorkspace.shared.icon(forFile: $0.url.path) }
        }
        .accessibilityLabel(game.name)
    }
}
