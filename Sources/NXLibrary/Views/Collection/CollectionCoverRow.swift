import SwiftUI
import NXLibraryCore

/// Collection's single row of portrait covers (Main.xaml PART_ListGameItems,
/// 400 high). Selene units on the stage: covers 188 × 265, 14 apart, radius 12.
/// The selected cover grows with the focus ring and sits on top; the selection
/// walks to the anchor slot and then the row slides (`CollectionRow`).
struct CollectionCoverRow: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let games: [PortedGame]
    let selectedID: UUID?
    let steamGridDbApiKey: String
    let artwork: ArtworkStore
    let steamGridDB: SteamGridDBService
    let coverURL: (PortedGame) -> URL?
    let onSelect: (PortedGame) -> Void
    let onActivate: (PortedGame) -> Void

    /// Selene's list item margin (14 left).
    private static let startInset: CGFloat = 14

    var body: some View {
        let selected = selectedID.flatMap { id in games.firstIndex { $0.id == id } }
        let offset = selected.map(CollectionRow.scrollOffset(selectedIndex:)) ?? 0
        let window = visibleRange(offset: offset)
        ZStack(alignment: .topLeading) {
            ForEach(window.map { (index: $0, game: games[$0]) }, id: \.game.id) { entry in
                cover(entry.game, selected: entry.index == selected)
                    .offset(x: canvas.u(Self.startInset + CGFloat(entry.index - offset) * CollectionRow.pitch),
                            y: canvas.u((CollectionRow.bandHeight - CollectionRow.coverHeight) / 2))
                    .zIndex(entry.index == selected ? 10 : 0)
                    .transition(.identity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: canvas.u(CollectionRow.bandHeight), alignment: .topLeading)
        .animation(reduceMotion ? nil : SeleneTheme.cubicOut(0.18), value: selectedID)
        .animation(reduceMotion ? nil : SeleneTheme.cubicOut(0.18), value: games.map(\.id))
    }

    /// Covers from just left of the screen to just past its right edge.
    private func visibleRange(offset: Int) -> Range<Int> {
        guard !games.isEmpty else { return 0..<0 }
        let pitch = max(canvas.u(CollectionRow.pitch), 1)
        let before = Int((canvas.stageOrigin.x / pitch).rounded(.up)) + 2
        let across = Int((canvas.size.width / pitch).rounded(.up)) + 3
        let lower = max(0, offset - before)
        let upper = min(games.count, offset + across)
        return lower..<max(lower, upper)
    }

    private func cover(_ game: PortedGame, selected: Bool) -> some View {
        let w = canvas.u(CollectionRow.coverWidth), h = canvas.u(CollectionRow.coverHeight)
        let face = RoundedRectangle(cornerRadius: canvas.u(12), style: .continuous)
        return ZStack {
            SpotlightTileArtwork(game: game, side: h, width: w, coverFirst: true,
                                 steamGridDbApiKey: steamGridDbApiKey,
                                 artwork: artwork, steamGridDB: steamGridDB,
                                 coverURL: coverURL(game))
                .clipShape(face)
                .shadow(color: .black.opacity(0.55), radius: canvas.u(9))
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
    }
}
