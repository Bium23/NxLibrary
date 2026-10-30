import SwiftUI
import AppKit
import NXLibraryCore

/// A band's title (Selene's SeleneBandLabel): 21 SemiBold, 2 above, 14 below.
struct DetailsBandTitle: View {
    @Environment(\.seleneCanvas) private var canvas

    let text: String

    var body: some View {
        Text(text)
            .seleneFont(21, .semibold)
            .foregroundColor(SeleneTheme.ink)
            .padding(.top, canvas.u(2))
            .padding(.bottom, canvas.u(14))
    }
}

/// Band 1: the game's screenshots, in Selene DetailsStage's tiles (272 × 153).
/// The title shows once the screenshots are known or while there are some; a
/// click focuses a tile and a double click opens it.
struct DetailsScreenshotsBand: View {
    @Environment(\.seleneCanvas) private var canvas

    let titleID: String
    let urls: [URL]
    let known: Bool
    let focusedIndex: Int?
    let artwork: ArtworkStore
    let onFocus: (Int) -> Void
    let onOpen: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !urls.isEmpty || known {
                DetailsBandTitle(text: "Screenshots")
            }
            SpotlightScreenshotStrip(titleID: titleID, urls: urls, known: known,
                                     focusedIndex: focusedIndex, artwork: artwork,
                                     onSelect: onFocus, onActivate: onOpen,
                                     style: .details)
        }
    }
}

/// Your activity, the right column of band 2 (Selene's SeleneDetailsBand2b):
/// play time and last played over this week and the rank among your games.
/// The rank is hidden until the game has play time.
struct DetailsActivityColumn: View {
    @Environment(\.seleneCanvas) private var canvas

    let presentation: GameDetailPresentation

    static let width: CGFloat = 510

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailsBandTitle(text: "Your activity")
            VStack(alignment: .leading, spacing: canvas.u(14)) {
                HStack(alignment: .top, spacing: canvas.u(24)) {
                    cell("PLAY TIME", presentation.playtime)
                    cell("LAST PLAYED", presentation.lastPlayed)
                }
                HStack(alignment: .top, spacing: canvas.u(24)) {
                    cell("THIS WEEK", presentation.thisWeek)
                    if let rank = presentation.rank {
                        cell("RANK", rank)
                    }
                }
            }
        }
        .frame(width: canvas.u(Self.width), alignment: .topLeading)
    }

    private func cell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(2)) {
            Text(label)
                .seleneFont(12, .semibold)
                .foregroundColor(SeleneTheme.ink60)
            Text(value)
                .seleneFont(21, .semibold)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Band 3: more games from your own library (`MoreLikeThis`), Switch box
/// covers of 173 × 280 (`SwitchBoxArtCover`). A click focuses, a double
/// click opens the game on Spotlight.
struct DetailsMoreBand: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let games: [PortedGame]
    let focusedIndex: Int?
    let artwork: ArtworkStore
    let boxArt: BoxArtService
    let boxArtIndexVersion: Int
    let officialName: (PortedGame) -> String?
    let onFocus: (Int) -> Void
    let onOpen: (Int) -> Void

    /// Switch case proportions (`BoxArt`).
    static let width: CGFloat = 173
    static let height: CGFloat = 280
    static let gap: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailsBandTitle(text: "More like this")
            HStack(alignment: .top, spacing: canvas.u(Self.gap)) {
                ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                    tile(game, index: index, focused: focusedIndex == index)
                }
            }
        }
    }

    private func tile(_ game: PortedGame, index: Int, focused: Bool) -> some View {
        let w = canvas.u(Self.width), h = canvas.u(Self.height)
        let face = RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
        return ZStack {
            SwitchBoxArtCover(game: game, width: w, height: h, officialName: officialName(game),
                              boxArt: boxArt, artwork: artwork, indexVersion: boxArtIndexVersion)
                .clipShape(face)
            SeleneTileRing(cornerRadius: canvas.u(21), active: focused)
                .frame(width: w + canvas.u(14), height: h + canvas.u(14))
        }
        .frame(width: w, height: h)
        .shadow(color: .black.opacity(0.55), radius: canvas.u(9))
        .scaleEffect(focused ? 1.05 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: focused)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen(index) }
        .simultaneousGesture(TapGesture().onEnded { onFocus(index) })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name)
        .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
    }
}
