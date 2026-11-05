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
    /// Credited in the title when not the store or Title DB ("LaunchBox").
    let source: String?
    let known: Bool
    let focusedIndex: Int?
    let artwork: ArtworkStore
    let onFocus: (Int) -> Void
    let onOpen: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !urls.isEmpty || known {
                DetailsBandTitle(text: source.map { "Screenshots · \($0)" } ?? "Screenshots")
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

/// Band 2: the game's mods (`ModStore`), one Selene glass tile (272 × 153) per mod with its state, then Manage mods.
/// A click focuses a tile; a double click (or A) opens Game options → Mods, where mods are switched and ordered.
struct DetailsModsBand: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let mods: [LocalMod]
    let focusedIndex: Int?
    let onFocus: (Int) -> Void
    let onOpen: (Int) -> Void

    static let width: CGFloat = 272
    static let height: CGFloat = 153
    static let gap: CGFloat = 22
    /// Tiles shown before Manage mods; the panel lists every mod.
    static let maxTiles = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailsBandTitle(text: title)
            HStack(alignment: .top, spacing: canvas.u(Self.gap)) {
                ForEach(Array(Self.shown(mods).enumerated()), id: \.element.folderName) { index, mod in
                    tile(index: index, focused: focusedIndex == index) {
                        modFace(mod)
                    }
                    .accessibilityLabel("\(mod.folderName), \(Self.state(mod))")
                }
                let manage = Self.shown(mods).count
                tile(index: manage, focused: focusedIndex == manage) {
                    manageFace
                }
                .accessibilityLabel("Manage mods")
            }
        }
    }

    private var title: String {
        let on = mods.filter(\.isOn).count
        return on == 0 ? "Mods" : "Mods · \(on) on"
    }

    static func shown(_ mods: [LocalMod]) -> [LocalMod] { Array(mods.prefix(maxTiles)) }

    /// Tiles the band holds: the mods shown plus Manage mods.
    static func tileCount(_ mods: [LocalMod]) -> Int { shown(mods).count + 1 }

    static func state(_ mod: LocalMod) -> String { mod.romfs == nil ? "Not a mod" : mod.isOn ? "On" : "Off" }

    private func modFace(_ mod: LocalMod) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(8)) {
            MaterialIconView(.puzzle, size: 26)
                .foregroundColor(mod.isOn ? SeleneTheme.focus : SeleneTheme.ink60)
            Spacer(minLength: 0)
            Text(mod.folderName)
                .seleneFont(19, .semibold)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(2)
            Text(Self.state(mod))
                .seleneFont(15, .medium)
                .foregroundColor(mod.isOn ? SeleneTheme.ink82 : SeleneTheme.ink60)
        }
    }

    private var manageFace: some View {
        VStack(alignment: .leading, spacing: canvas.u(8)) {
            MaterialIconView(mods.isEmpty ? .add : .settings, size: 26)
                .foregroundColor(SeleneTheme.ink75)
            Spacer(minLength: 0)
            Text(mods.isEmpty ? "Add mods" : "Manage mods")
                .seleneFont(19, .semibold)
                .foregroundColor(SeleneTheme.ink)
            Text(mods.isEmpty ? "File mods, no rebuild" : mods.count > Self.maxTiles ? "All \(mods.count) mods" : "Order, folder, Remove")
                .seleneFont(15, .medium)
                .foregroundColor(SeleneTheme.ink60)
        }
    }

    private func tile<Face: View>(index: Int, focused: Bool, @ViewBuilder face: () -> Face) -> some View {
        let w = canvas.u(Self.width), h = canvas.u(Self.height)
        let shape = RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
        return ZStack {
            shape.fill(SeleneTheme.glass)
            shape.stroke(SeleneTheme.ink15, lineWidth: canvas.u(1))
            face()
                .padding(canvas.u(18))
                .frame(width: w, height: h, alignment: .topLeading)
            SeleneTileRing(cornerRadius: canvas.u(21), active: focused)
                .frame(width: w + canvas.u(14), height: h + canvas.u(14))
        }
        .frame(width: w, height: h)
        .shadow(color: .black.opacity(0.45), radius: canvas.u(9))
        .scaleEffect(focused ? 1.05 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: focused)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen(index) }
        .simultaneousGesture(TapGesture().onEnded { onFocus(index) })
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
    }
}
