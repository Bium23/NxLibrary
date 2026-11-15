import SwiftUI
import AppKit
import NXLibraryCore

/// Native-app artwork for non-nxnative entries, in the tile's layout role: a square
/// shows the app's own icon (or the player's pick), a portrait the cover. It never
/// asks Nintendo artwork services or writes the installed app.
struct CatalogNativeArtwork: View {
    let game: CatalogGame
    var role: LibraryArtworkRole = .cover
    /// The art's look (black and white while Steam installs the game); the Steam label stays sharp above it.
    var look: PortingTileLook = .normal
    var cornerRadius: CGFloat = 12
    @Environment(\.seleneCanvas) private var canvas
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                SeleneTheme.glassSolid
                SteamArtwork(game: game, slot: role.slot)
            }
            .portingLook(look, cornerRadius: canvas.u(cornerRadius))
            Text("Steam").seleneFont(12, .semibold).foregroundColor(SeleneTheme.ink)
                .padding(.horizontal, canvas.u(8)).padding(.vertical, canvas.u(4))
                .background(Capsule().fill(SeleneTheme.glassSolid)).padding(canvas.u(9))
        }
        .accessibilityLabel(game.name)
    }
}
