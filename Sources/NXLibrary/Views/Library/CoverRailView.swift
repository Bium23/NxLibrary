import SwiftUI
import AppKit
import NXLibraryCore

/// Shared geometry for the library rail and the hero's bottom reservation.
enum LibraryRailLayout {
    static let tileSpacing: CGFloat = 18
    static let verticalPadding: CGFloat = 16
    static let labelSpacing: CGFloat = 8
    static let labelHeight: CGFloat = 14
    static let commandBarHeight: CGFloat = 36
    static let heroGap: CGFloat = 24

    static func tileSize(for metrics: SeleneLayoutMetrics) -> CGFloat {
        if metrics.width >= 1500 { return 184 }
        if metrics.width >= 1280 { return 168 }
        return 156
    }

    static func reservedHeight(for metrics: SeleneLayoutMetrics) -> CGFloat {
        tileSize(for: metrics) + labelSpacing + labelHeight + verticalPadding * 2
    }

    static func heroBottomInset(for metrics: SeleneLayoutMetrics,
                                showsCommandBar: Bool) -> CGFloat {
        reservedHeight(for: metrics)
            + (showsCommandBar ? commandBarHeight : 0)
            + heroGap
    }
}

struct CoverRailView: View {
    let games: [PortedGame]
    let selectedID: UUID?
    let images: [UUID: NSImage]
    let metrics: SeleneLayoutMetrics
    let focusActive: Bool
    let reduceMotion: Bool
    let onSelect: (UUID) -> Void
    let onOpen: (PortedGame) -> Void

    private var tileSize: CGFloat {
        LibraryRailLayout.tileSize(for: metrics)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: LibraryRailLayout.tileSpacing) {
                    ForEach(games) { game in
                        KeyArtTile(
                            game: game,
                            image: images[game.id],
                            selected: game.id == selectedID,
                            focused: focusActive && game.id == selectedID,
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
                       alignment: .center)
                .padding(.horizontal, metrics.margin)
                .padding(.vertical, LibraryRailLayout.verticalPadding)
            }
            .onChange(of: selectedID) { id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onAppear {
                guard let id = selectedID else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}

private struct KeyArtTile: View {
    let game: PortedGame
    let image: NSImage?
    let selected: Bool
    let focused: Bool
    let side: CGFloat
    let reduceMotion: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    private let radius: CGFloat = 14

    var body: some View {
        VStack(spacing: LibraryRailLayout.labelSpacing) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(nsImage: GameIconProvider.icon(for: game))
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: side, height: side)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(selected ? 0.52 : 0.22)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(SeleneTheme.ink.opacity(selected ? 0 : 0.10), lineWidth: 1)
            )
            .seleneFocus(focused, radius: radius)
            .shadow(color: .black.opacity(selected ? 0.55 : 0.32),
                    radius: selected ? 14 : 10, x: 0, y: selected ? 6 : 4)
            .scaleEffect(reduceMotion ? 1 : (selected ? 1.06 : 1))

            Text(game.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SeleneTheme.ink.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: side, height: LibraryRailLayout.labelHeight)
                .opacity(selected ? 1 : 0)
        }
        .frame(width: side)
        .opacity(selected ? 1 : 0.62)
        .saturation(selected ? 1 : 0.85)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture { onSelect() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: selected)
    }
}
