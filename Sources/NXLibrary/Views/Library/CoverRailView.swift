import SwiftUI
import AppKit
import NXLibraryCore

struct CoverRailView: View {
    let games: [PortedGame]
    let selectedID: UUID?
    let coverImages: [UUID: NSImage]
    let metrics: SeleneLayoutMetrics
    let onSelect: (UUID) -> Void
    let onOpen: (PortedGame) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 15) {
                    ForEach(games) { game in
                        CoverCard(
                            game: game,
                            image: coverImages[game.id],
                            selected: game.id == selectedID,
                            metrics: metrics,
                            onSelect: { onSelect(game.id) },
                            onOpen: { onOpen(game) }
                        )
                        .id(game.id)
                    }
                }
                .frame(minWidth: metrics.width, alignment: .center)
                .padding(.horizontal, metrics.margin)
                .padding(.bottom, 14)
                .padding(.top, 8)
            }
            .onChange(of: selectedID) { id in
                guard let id else { return }
                withAnimation(SeleneTheme.quick) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}

private struct CoverCard: View {
    let game: PortedGame
    let image: NSImage?
    let selected: Bool
    let metrics: SeleneLayoutMetrics
    let onSelect: () -> Void
    let onOpen: () -> Void

    private var width: CGFloat {
        selected ? metrics.railCardWidth * 1.08 : metrics.railCardWidth
    }

    private var height: CGFloat {
        selected ? metrics.railCardHeight * 1.08 : metrics.railCardHeight
    }

    var body: some View {
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
            .frame(width: width, height: height)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(selected ? 0.55 : 0.25)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(width: width, height: height)

            if selected {
                Text(game.name)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 7)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: SeleneTheme.coverRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SeleneTheme.coverRadius, style: .continuous)
                .strokeBorder(selected ? SeleneTheme.focus : SeleneTheme.ink.opacity(0.08),
                              lineWidth: selected ? 2 : 0.8)
        )
        .shadow(color: .black.opacity(selected ? 0.55 : 0.32),
                radius: selected ? 18 : 10, x: 0, y: selected ? 9 : 5)
        .opacity(selected ? 1 : 0.76)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture { onSelect() }
        .accessibilityLabel(game.name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
