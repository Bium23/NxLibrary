import SwiftUI
import NXLibraryCore

/// Collection's single row of portrait covers (Main.xaml PART_ListGameItems,
/// 400 high). Selene units on the stage: Switch box covers 172 × 278, 14 apart, radius 12.
/// The selected cover grows with the focus ring and sits on top; the selection
/// walks to the anchor slot and then the row slides (`CollectionRow`). The covers sit in the row and one camera
/// slides the whole row, as in Spotlight (`SpotlightRowGeometry`), so it moves as one piece.
struct CollectionCoverRow: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let games: [CatalogGame]
    let selectedID: UUID?
    let artwork: ArtworkStore
    let boxArt: BoxArtService
    let boxArtIndexVersion: Int
    /// The official name, once store metadata has it.
    let officialName: (PortedGame) -> String?
    /// Asks for a game's store metadata (its official name) when its cover shows.
    let needsMetadata: (PortedGame) -> Void
    /// The porting look of a game's cover (`PortingTileLook`).
    var tileLook: (PortedGame) -> PortingTileLook = { _ in .normal }
    let onSelect: (CatalogGame) -> Void
    let onActivate: (CatalogGame) -> Void

    /// The first cover lines up with Spotlight's 80 margin (Selene's list had 14).
    private static let startInset: CGFloat = 80

    /// A critically damped spring of about the old 0.18 s: quick presses retarget it without a surge.
    private static let glide = Animation.spring(response: 0.18, dampingFraction: 1)

    var body: some View {
        let selected = selectedID.flatMap { id in games.firstIndex { $0.id == id } }
        let offset = selected.map(CollectionRow.scrollOffset(selectedIndex:)) ?? 0
        let window = visibleRange(offset: offset)
        ZStack(alignment: .topLeading) {
            ForEach(window.map { (index: $0, game: games[$0]) }, id: \.game.id) { entry in
                cover(entry.game, selected: entry.index == selected)
                    .offset(x: canvas.u(Self.startInset + CGFloat(entry.index) * CollectionRow.pitch),
                            y: canvas.u((CollectionRow.bandHeight - CollectionRow.coverHeight) / 2))
                    .zIndex(entry.index == selected ? 10 : 0)
                    .transition(.identity)
            }
        }
        // The camera: the one slide of the whole row.
        .offset(x: canvas.u(-CGFloat(offset) * CollectionRow.pitch))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: canvas.u(CollectionRow.bandHeight), alignment: .topLeading)
        .animation(reduceMotion ? nil : Self.glide, value: selectedID)
        .animation(reduceMotion ? nil : Self.glide, value: games.map(\.id))
    }

    /// Covers from a few left of the screen to a few past its right edge (the same spare as Spotlight's row).
    private func visibleRange(offset: Int) -> Range<Int> {
        let pitch = max(canvas.u(CollectionRow.pitch), 1)
        return SpotlightRowGeometry.window(count: games.count, offset: offset,
                                           tilesLeftOfStage: Int((canvas.stageOrigin.x / pitch).rounded(.up)),
                                           tilesAcross: Int((canvas.size.width / pitch).rounded(.up)))
    }

    private func cover(_ game: CatalogGame, selected: Bool) -> some View {
        let w = canvas.u(CollectionRow.coverWidth), h = canvas.u(CollectionRow.coverHeight)
        let face = RoundedRectangle(cornerRadius: canvas.u(12), style: .continuous)
        return ZStack {
            Group {
                if let native = game.nxnativeGame {
            SwitchBoxArtCover(game: native, width: w, height: h, officialName: officialName(native),
                              boxArt: boxArt, artwork: artwork, indexVersion: boxArtIndexVersion)
                .portingLook(tileLook(native), cornerRadius: canvas.u(12))
                .frame(width: w, height: h)
                .clipShape(face)
                // One picture that grows and slides whole: a drawn cover's title, a lock or build progress would
                // otherwise snap to the pixel grid on their own at every step and shake against the cover.
                .drawingGroup()
                .shadow(color: .black.opacity(0.55), radius: canvas.u(9))
                } else {
                    CatalogNativeArtwork(game: game).frame(width: w, height: h).clipShape(face)
                }
            }
            SeleneShine(cornerRadius: canvas.u(12), active: selected)
                .frame(width: w, height: h)
            SeleneTileRing(cornerRadius: canvas.u(18), active: selected)
                .frame(width: w + canvas.u(12), height: h + canvas.u(12))
        }
        .frame(width: w, height: h)
        .scaleEffect(selected ? CollectionRow.selectedScale : 1)
        .contentShape(Rectangle())
        // The single click selects at once; it does not wait for a possible double click.
        .onTapGesture(count: 2) { onActivate(game) }
        .simultaneousGesture(TapGesture().onEnded { onSelect(game) })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .task(id: game.id) { if let native = game.nxnativeGame { needsMetadata(native) } }
    }
}
