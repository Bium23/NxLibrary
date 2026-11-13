import SwiftUI
import AppKit
import NXLibraryCore

/// Native-app artwork for non-nxnative entries, in the tile's layout role: a square
/// shows the app's own icon (or the player's pick), a portrait the cover. It never
/// asks Nintendo artwork services or writes the installed app.
struct CatalogNativeArtwork: View {
    let game: CatalogGame
    var role: LibraryArtworkRole = .cover
    @Environment(\.seleneCanvas) private var canvas
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SeleneTheme.glassSolid
            SteamArtwork(game: game, slot: role.slot)
            Text("Steam").seleneFont(12, .semibold).foregroundColor(SeleneTheme.ink)
                .padding(.horizontal, canvas.u(8)).padding(.vertical, canvas.u(4))
                .background(Capsule().fill(SeleneTheme.glassSolid)).padding(canvas.u(9))
        }
        .accessibilityLabel(game.name)
    }
}
