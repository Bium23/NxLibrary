import SwiftUI
import NXLibraryCore

/// Spotlight's single row of square tiles (Main.xaml SeleneGameRow + SeleneTileStyle).
///
/// Geometry in Selene units, relative to the stage: the row's top edge is the
/// view's top (120 + 10 on the stage). Each item is `1 + 174·s + 3` wide (item
/// margin 1/3, tile host 174 = 160 + 2·7), where `s` is 1.3 for the selected
/// tile and 1 otherwise; the selected tile grows through its frame so the
/// neighbours move. The selection walks to the third slot and then stays there
/// while the row slides (HomeNav.AnchorSlot). The row's 80 start padding puts
/// the first slot's face at x = 80.
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
    let onSelect: (SpotlightItem) -> Void
    let onActivate: (SpotlightItem) -> Void

    @State private var titleVisible = false
    @State private var titleTask: Task<Void, Never>?

    static let pitch: CGFloat = 178          // 1 + 174 + 3
    static let host: CGFloat = 174           // 160 + 2 × 7
    static let grow: CGFloat = 1.3
    static let rowStart: CGFloat = 72        // 80 start padding − 8 (row margin −88 + side margin 80)

    var body: some View {
        // A key that is not in the row (yet) means no selection, not the first item.
        let selected = selectedKey.flatMap { key in items.firstIndex { $0.key == key } }
        let offset = selected.map(SpotlightState.scrollOffset(selectedIndex:)) ?? 0
        let window = visibleRange(offset: offset)
        ZStack(alignment: .topLeading) {
            ForEach(window.map { (index: $0, item: items[$0]) }, id: \.item.key) { entry in
                let index = entry.index, item = entry.item
                let isSelected = index == selected
                tile(item, selected: isSelected)
                    .offset(x: canvas.u(x(of: index, selected: selected, offset: offset)),
                            y: canvas.u(item.key == liftedKey ? 3 - 12 : 3))
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
                    .offset(x: canvas.u(x(of: selected, selected: selected, offset: offset)
                                        + 1 + Self.host * Self.grow + 16),
                            y: canvas.u(3 + 7 * Self.grow + 160 + 14))
                    .opacity(titleVisible ? 1 : 0)
                    .allowsHitTesting(false)
                    .zIndex(11)
            }
            if let isEmptyFilter {
                emptyMessage(isEmptyFilter)
                    .offset(x: canvas.u(80 + 560), y: canvas.u(46 - 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: canvas.u(260), alignment: .topLeading)
        // A glide, not a jump: the row and the growing tile ease over 0.32 s
        // (under reduce motion the ring and size still fade, without the slide).
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SeleneTheme.cubicOut(0.32), value: selectedKey)
        .animation(reduceMotion ? nil : SeleneTheme.cubicOut(0.32), value: items.map(\.key))
        .animation(reduceMotion ? nil : SeleneTheme.cubicOut(0.32), value: liftedKey)
        .onAppear { scheduleTitle(delay: 0) }
        .onChange(of: selectedKey) { _ in scheduleTitle(delay: 0.23) }
        .onDisappear { titleTask?.cancel() }
    }

    /// Left edge of item `index` (its 1u margin included), stage units.
    private func x(of index: Int, selected: Int?, offset: Int) -> CGFloat {
        let base = Self.rowStart + CGFloat(index - offset) * Self.pitch
        guard let selected, index > selected else { return base }
        return base + Self.host * (Self.grow - 1)
    }

    /// Items from just left of the screen to just past its right edge; tiles
    /// outside never render, so a long library stays cheap.
    private func visibleRange(offset: Int) -> Range<Int> {
        guard !items.isEmpty else { return 0..<0 }
        let leftSpare = canvas.stageOrigin.x / max(canvas.u(Self.pitch), 1)
        let before = Int(leftSpare.rounded(.up)) + 2
        let across = Int((canvas.size.width / max(canvas.u(Self.pitch), 1)).rounded(.up)) + 3
        let lower = max(0, offset - before)
        let upper = min(items.count, offset + across)
        return lower..<max(lower, upper)
    }

    private func tile(_ item: SpotlightItem, selected: Bool) -> some View {
        let scale = selected ? Self.grow : 1
        return ZStack(alignment: .topLeading) {
            face(item, selected: selected)
                .padding(canvas.u(7))
            SeleneTileRing(cornerRadius: canvas.u(19), active: selected)
                .frame(width: canvas.u(Self.host), height: canvas.u(Self.host))
        }
        .frame(width: canvas.u(Self.host), height: canvas.u(Self.host), alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: canvas.u(Self.host * scale), height: canvas.u(Self.host * scale), alignment: .topLeading)
        .padding(.leading, canvas.u(1))
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
            case .card(let card):
                face.fill(SeleneTheme.glass)
                    .overlay(face.strokeBorder(SeleneTheme.ink15, lineWidth: max(1, canvas.u(1))))
                    .overlay(MaterialIconView(card.icon, size: 60).foregroundColor(SeleneTheme.ink))
            }
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
        return VStack(alignment: .leading, spacing: canvas.u(8)) {
            Text(title).seleneFont(30, .semibold).foregroundColor(SeleneTheme.ink)
            Text(hint).seleneFont(19).foregroundColor(SeleneTheme.ink60)
                .frame(maxWidth: canvas.u(520), alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .allowsHitTesting(false)
    }
}
