import SwiftUI
import NXLibraryCore

/// Spotlight's single row of square tiles (Main.xaml SeleneGameRow + SeleneTileStyle).
///
/// Geometry in Selene units, relative to the stage (`SpotlightRowGeometry`): the row's top edge is the view's top
/// (120 + 10 on the stage), and the row's 80 start padding puts the first slot's face at x = 80. The tiles sit in
/// the row and one camera slides the whole row, so it moves as one piece however quickly the selection moves.
struct SpotlightRowView: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let items: [SpotlightItem]
    let gamesByID: [UUID: PortedGame]
    let selectedKey: String?
    /// The tile lifted for moving: raised 12u, its ring stays.
    var liftedKey: String? = nil
    let isEmptyFilter: LibraryFilter?
    let artwork: ArtworkStore
    /// The porting look of a game's tile (`PortingTileLook`).
    var tileLook: (PortedGame) -> PortingTileLook = { _ in .normal }
    /// Mods' art for the Mods card's face (up to four); empty draws Selene's own face.
    var modsCover: [URL] = []
    let onSelect: (SpotlightItem) -> Void
    let onActivate: (SpotlightItem) -> Void

    @State private var titleVisible = false
    @State private var titleTask: Task<Void, Never>?
    /// The tile last lifted for moving, while it is still the selection.
    @State private var lastLifted: String?

    static let pitch = SpotlightRowGeometry.pitch
    static let host = SpotlightRowGeometry.host
    static let grow = SpotlightRowGeometry.grow

    /// The row's glide: a critically damped spring of about the old 0.32 s. A quick run of presses retargets it
    /// and it carries its speed on (a timing curve restarted at full speed on every press, so the row surged).
    static let glide = Animation.spring(response: 0.32, dampingFraction: 1)

    var body: some View {
        // A key that is not in the row (yet) means no selection, not the first item.
        let selected = selectedKey.flatMap { key in items.firstIndex { $0.key == key } }
        let offset = selected.map(SpotlightState.scrollOffset(selectedIndex:)) ?? 0
        let window = visibleRange(offset: offset)
        // The one value every tile and the camera glide on (`SpotlightRowGeometry`).
        let position = selected.map { CGFloat($0) } ?? SpotlightRowGeometry.noSelection
        // While a tile is lifted, and after it is put down until the selection moves on, only it is grown: the
        // tiles it passes swap places under it at their own size.
        let alone = liftedKey != nil || (lastLifted != nil && lastLifted == selectedKey)
        ZStack(alignment: .topLeading) {
            ForEach(window.map { (index: $0, item: items[$0]) }, id: \.item.key) { entry in
                let index = entry.index, item = entry.item
                let isSelected = index == selected
                tile(item, selected: isSelected)
                    .modifier(TileGlide(position: position, index: CGFloat(index),
                                        rise: item.key == liftedKey ? 3 - 12 : 3,
                                        grown: alone ? isSelected : nil, unit: canvas.u(1)))
                    .zIndex(isSelected ? 10 : 0)
                    .transition(.identity)
            }
            if let selected {
                let item = items[selected]
                Text(title(of: item))
                    .seleneFont(22)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(1)
                    .frame(width: canvas.u(420), alignment: .leading)
                    .offset(x: canvas.u(SpotlightRowGeometry.place(of: selected, selected: selected)
                                        + 1 + Self.host * Self.grow + 16),
                            y: canvas.u(3 + 7 * Self.grow + 160 + 14))
                    .opacity(titleVisible ? 1 : 0)
                    .allowsHitTesting(false)
                    .zIndex(11)
            }
            if let isEmptyFilter {
                // Beside the last card, whatever the card count and selection, never over them.
                emptyMessage(isEmptyFilter)
                    .offset(x: canvas.u(SpotlightRowGeometry.place(of: items.count, selected: selected) + 32),
                            y: canvas.u(3 + Self.host / 2 - 26))
                    .transition(.opacity)
            }
        }
        // The camera: the one slide of the whole row, on the tiles' own glide.
        .modifier(CameraGlide(position: position, unit: canvas.u(1)))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: canvas.u(260), alignment: .topLeading)
        // A glide, not a jump: the row and the growing tile glide together
        // (under reduce motion the ring and size still fade, without the slide).
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Self.glide, value: selectedKey)
        .animation(reduceMotion ? nil : Self.glide, value: items.map(\.key))
        .animation(reduceMotion ? nil : Self.glide, value: liftedKey)
        .animation(.easeOut(duration: 0.3), value: isEmptyFilter)
        .onAppear { scheduleTitle(delay: 0) }
        .onChange(of: selectedKey) { key in
            if key != lastLifted { lastLifted = nil }
            scheduleTitle(delay: 0.23)
        }
        .onChange(of: liftedKey) { key in
            if let key { lastLifted = key }
        }
        .onDisappear { titleTask?.cancel() }
    }

    /// Items from a few tiles left of the screen to a few past its right edge; tiles
    /// outside never render, so a long library stays cheap.
    private func visibleRange(offset: Int) -> Range<Int> {
        let pitch = max(canvas.u(Self.pitch), 1)
        return SpotlightRowGeometry.window(count: items.count, offset: offset,
                                           tilesLeftOfStage: Int((canvas.stageOrigin.x / pitch).rounded(.up)),
                                           tilesAcross: Int((canvas.size.width / pitch).rounded(.up)))
    }

    /// A tile at its own size; `TileGlide` places and grows it.
    private func tile(_ item: SpotlightItem, selected: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            face(item, selected: selected)
                .padding(canvas.u(7))
            SeleneTileRing(cornerRadius: canvas.u(19), active: selected)
                .frame(width: canvas.u(Self.host), height: canvas.u(Self.host))
        }
        .frame(width: canvas.u(Self.host), height: canvas.u(Self.host), alignment: .topLeading)
        .contentShape(Rectangle())
        // The single click selects at once; it does not wait for a possible double click.
        .onTapGesture(count: 2) { onActivate(item) }
        .simultaneousGesture(TapGesture().onEnded { onSelect(item) })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title(of: item))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func face(_ item: SpotlightItem, selected: Bool) -> some View {
        let side = canvas.u(160)
        let face = RoundedRectangle(cornerRadius: canvas.u(12), style: .continuous)
        ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous).fill(SeleneTheme.ink15)
                switch item {
                case .game(let id):
                    if let game = gamesByID[id] {
                        SpotlightTileArtwork(game: game, side: side,
                                             artwork: artwork, ownIconFirst: true)
                            .portingLook(tileLook(game), cornerRadius: canvas.u(12))
                            .frame(width: side, height: side)
                            .clipShape(face)
                    }
                case .card(.mods):
                    ModsCardCover(urls: modsCover, side: side)
                        .clipShape(face)
                        .overlay(face.strokeBorder(SeleneTheme.ink15, lineWidth: max(1, canvas.u(1))))
                case .card(let card):
                    face.fill(SeleneTheme.glass)
                        .overlay(face.strokeBorder(SeleneTheme.ink15, lineWidth: max(1, canvas.u(1))))
                        .overlay(MaterialIconView(card.icon, size: 60).foregroundColor(SeleneTheme.ink))
                }
            }
            .frame(width: side, height: side)
            // Drawn as one picture that grows and slides whole. Words and glyphs on a face (a card's icon, a
            // game's lock or build progress) were otherwise redrawn at every step of the grow and the glide and
            // snapped to the pixel grid on their own, so they shook against their tile in a quick run of presses.
            // The shine is a Core Animation layer and stays outside.
            .drawingGroup()
            SeleneShine(cornerRadius: canvas.u(12), active: selected)
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.55), radius: canvas.u(9))
    }

    private func title(of item: SpotlightItem) -> String {
        switch item {
        case .card(let card): return card.title
        case .game(let id): return gamesByID[id]?.name ?? ""
        }
    }

    /// The title hides at once on a move and fades in (0.2 s) once the row has settled.
    private func scheduleTitle(delay: Double) {
        titleTask?.cancel()
        var hide = Transaction()
        hide.disablesAnimations = true
        withTransaction(hide) { titleVisible = false }
        titleTask = Task { @MainActor in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { titleVisible = true }
        }
    }

    private func emptyMessage(_ filter: LibraryFilter) -> some View {
        let (title, hint): (String, String) = {
            switch filter {
            case .installed: return ("Nothing installed", "Build a game and it shows up here.")
            case .recentlyPlayed: return ("Nothing played lately", "Games you play show up here.")
            case .favorites: return ("No favorites yet", "Choose the heart on a game to add it to your favorites.")
            case .notPlayed: return ("You've started everything", "Every game in your library has been played at least once.")
            case .all: return ("No games yet", "Add a game to start your collection.")
            }
        }()
        return VStack(alignment: .leading, spacing: canvas.u(6)) {
            Text(title).seleneFont(22, .medium).foregroundColor(SeleneTheme.ink90)
            Text(hint).seleneFont(16).foregroundColor(SeleneTheme.ink60)
                .frame(maxWidth: canvas.u(380), alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .allowsHitTesting(false)
    }
}

/// A tile's place and size, worked out from the selection's position (`SpotlightRowGeometry`) at every frame of the
/// glide. Each tile glides the same value as its neighbours and the camera, so the row keeps its gaps in any rhythm
/// of presses. `grown` overrides the size while a tile is lifted (true for it, false for the rest).
private struct TileGlide: GeometryEffect {
    var position: CGFloat
    var index: CGFloat
    /// The tile's top edge in the row, in Selene units (raised while lifted).
    var rise: CGFloat
    let grown: Bool?
    let unit: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(position, index), rise) }
        set {
            position = newValue.first.first
            index = newValue.first.second
            rise = newValue.second
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let scale = grown.map { $0 ? SpotlightRowGeometry.grow : 1 }
            ?? SpotlightRowGeometry.scale(of: index, at: position)
        // The 1u is the item's start margin.
        let x = (SpotlightRowGeometry.place(of: index, at: position) + 1) * unit
        return ProjectionTransform(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: rise * unit))
    }
}

/// The row's camera on the tiles' own glide.
private struct CameraGlide: GeometryEffect {
    var position: CGFloat
    let unit: CGFloat

    var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: SpotlightRowGeometry.camera(at: position) * unit, y: 0))
    }
}

/// The Mods card's face, filling the tile like a game icon: four mods' art as a mosaic (one when fewer), blurred
/// and dimmed, with the puzzle glyph in the middle like the other cards. With no art yet the ground is Selene's
/// accent gradient; the two crossfade under the glyph. Only the art GameBanana shows for the mods. New art comes
/// already decoded (`ModStoreHost`) and the whole mosaic crossfades, never one cell after another.
struct ModsCardCover: View {
    @Environment(\.seleneCanvas) private var canvas
    let urls: [URL]
    let side: CGFloat

    /// The cells' decode size.
    static let pixelSize = 700

    var body: some View {
        ZStack {
            LinearGradient(colors: [SeleneTheme.focus.opacity(0.85), SeleneTheme.glassSolid],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if !urls.isEmpty {
                mosaic
                    .blur(radius: canvas.u(5), opaque: true)
                    .overlay(Color.black.opacity(0.35))
                    .id(urls)
                    .transition(.opacity)
            }
            MaterialIconView(.puzzle, size: 60)
                .foregroundColor(SeleneTheme.ink)
                .shadow(color: .black.opacity(0.45), radius: canvas.u(8))
        }
        .frame(width: side, height: side)
        .animation(.easeOut(duration: 0.4), value: urls)
        .drawingGroup()
    }

    @ViewBuilder
    private var mosaic: some View {
        if urls.count >= 4 {
            let half = side / 2
            VStack(spacing: 0) {
                HStack(spacing: 0) { cell(urls[0], half); cell(urls[1], half) }
                HStack(spacing: 0) { cell(urls[2], half); cell(urls[3], half) }
            }
            .frame(width: side, height: side)
        } else {
            cell(urls[0], side)
        }
    }

    private func cell(_ url: URL, _ size: CGFloat) -> some View {
        GameBananaImageView(url: url, maxPixelSize: Self.pixelSize)
            .frame(width: size, height: size)
            .clipped()
    }
}
