import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

/// Native-app artwork for non-nxnative entries, in the tile's layout role: a square
/// shows the app's own icon (or the player's pick), a portrait the cover. It never
/// asks Nintendo artwork services or writes the installed app.
struct CatalogNativeArtwork: View {
    let game: CatalogGame
    var role: LibraryArtworkRole = .cover
    /// The art's look (black and white while Steam installs the game).
    var look: PortingTileLook = .normal
    var cornerRadius: CGFloat = 12
    @Environment(\.seleneCanvas) private var canvas
    var body: some View {
        // No source label on the art: the page's Platform says Steam (maintainer's call, 15 Nov 2026).
        ZStack {
            SeleneTheme.glassSolid
            SteamArtwork(game: game, slot: role.slot)
        }
        .portingLook(look, cornerRadius: canvas.u(cornerRadius))
        .accessibilityLabel(game.name)
    }
}
