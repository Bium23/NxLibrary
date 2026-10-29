import SwiftUI
import AppKit
import NXLibraryCore

/// Shared geometry for the library rail and the hero's bottom reservation.
enum LibraryRailLayout {
    static let tileSpacing: CGFloat = 22
    static let commandBarHeight: CGFloat = 36
    static let filterTopPadding: CGFloat = 22
    static let filterHeight: CGFloat = 34
    static let filterRailGap: CGFloat = 10
    static let contentGap: CGFloat = 36

    static func tileSize(for metrics: SeleneLayoutMetrics, expanded: Bool) -> CGFloat {
        if expanded {
            if metrics.width >= 1500 { return 144 }
            if metrics.width >= 1280 { return 136 }
            return 128
        }
        if metrics.width >= 1500 { return 200 }
        if metrics.width >= 1280 { return 184 }
        return 168
    }

    static func verticalPadding(expanded: Bool) -> CGFloat {
        expanded ? 6 : 14
    }

    static func reservedHeight(for metrics: SeleneLayoutMetrics,
                               expanded: Bool) -> CGFloat {
        tileSize(for: metrics, expanded: expanded)
            + verticalPadding(expanded: expanded) * 2
    }

    static func heroContentTopInset(for metrics: SeleneLayoutMetrics,
                                    expanded: Bool) -> CGFloat {
        filterTopPadding + filterHeight + filterRailGap
            + reservedHeight(for: metrics, expanded: expanded) + contentGap
    }
}

/// The PS5-style library row: the app icons from Applications, not store art.
/// The row is bottom-aligned, centered when it fits and scrollable when it does
/// not. Selecting a game never changes the row's baseline.
struct CoverRailView: View {
    let games: [PortedGame]
    let selectedID: UUID?
    let metrics: SeleneLayoutMetrics
    let expanded: Bool
    let reduceMotion: Bool
    let onSelect: (UUID) -> Void
    let onOpen: (PortedGame) -> Void

    private var tileSize: CGFloat {
        LibraryRailLayout.tileSize(for: metrics, expanded: expanded)
    }

    private var needsScrolling: Bool {
        let contentWidth = CGFloat(games.count) * tileSize
            + CGFloat(max(0, games.count - 1)) * LibraryRailLayout.tileSpacing
        return contentWidth > metrics.width - metrics.margin * 2
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: LibraryRailLayout.tileSpacing) {
                    ForEach(games) { game in
                        AppIconTile(
                            game: game,
                            selected: game.id == selectedID,
                            side: tileSize,
                            reduceMotion: reduceMotion,
                            onSelect: { onSelect(game.id) },
                            onOpen: { onOpen(game) }
                        )
                        .id(game.id)
                        .zIndex(game.id == selectedID ? 1 : 0)
                    }
                }
                .frame(minWidth: max(0, metrics.width - metrics.margin * 2),
                       alignment: .leading)
                .padding(.horizontal, metrics.margin)
                .padding(.vertical, LibraryRailLayout.verticalPadding(expanded: expanded))
            }
            .onChange(of: selectedID) { id in
                guard let id, needsScrolling else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onAppear {
                guard let id = selectedID, needsScrolling else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}

private struct AppIconTile: View {
    let game: PortedGame
    let selected: Bool
    let side: CGFloat
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(nsImage: GameIconProvider.icon(for: game))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: side, height: side)
                .shadow(color: .black.opacity(selected ? 0.48 : 0.28),
                        radius: selected ? 16 : 10,
                        x: 0, y: selected ? 7 : 4)
                .overlay {
                    if selected {
                        ZStack {
                            RoundedRectangle(cornerRadius: side * 0.22,
                                             style: .continuous)
                                .strokeBorder(.black.opacity(0.58), lineWidth: 4)
                            RoundedRectangle(cornerRadius: side * 0.22,
                                             style: .continuous)
                                .strokeBorder(SeleneTheme.focus, lineWidth: 2)
                        }
                        .padding(side * 0.05)
                    }
                }
                .scaleEffect(reduceMotion ? 1 : (selected ? 1.10 : 1),
                             anchor: .bottom)
        }
        .frame(width: side, height: side, alignment: .bottom)
        .opacity(selected ? 1 : 0.90)
        .contentShape(RoundedRectangle(cornerRadius: side * 0.22,
                                       style: .continuous))
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture { onSelect() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18),
                   value: selected)
    }

    private let onOpen: () -> Void
    private let onSelect: () -> Void

    init(game: PortedGame,
         selected: Bool,
         side: CGFloat,
         reduceMotion: Bool,
         onSelect: @escaping () -> Void,
         onOpen: @escaping () -> Void) {
        self.game = game
        self.selected = selected
        self.side = side
        self.reduceMotion = reduceMotion
        self.onSelect = onSelect
        self.onOpen = onOpen
    }
}
