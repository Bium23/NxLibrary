import SwiftUI
import AppKit
import NXLibraryCore

/// A band's title (Selene's SeleneBandLabel): 21 SemiBold, 2 above, 14 below.
struct DetailsBandTitle: View {
    @Environment(\.seleneCanvas) private var canvas

    let text: String
    /// Canvas units; the store's rows are a little larger than the game page's bands.
    var size: CGFloat = 21

    var body: some View {
        Text(text)
            .seleneFont(size, .semibold)
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

/// The game's mods, between Build & Sources and More like this. Left to right (`ModsBandLayout`): installed mods (`ModStore`, at most 5) with their state,
/// Manage mods, the GameBanana mods that work (image, name, author, Installed / Update), then status tiles (Retry, the
/// "Is this the right game?" candidates, Wrong game?…). The row slides so the focused tile stays on screen. A click
/// focuses a tile; a double click (or A) opens it.
struct DetailsModsBand: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let mods: [LocalMod]
    /// GameBanana records of installed mods, by GameBanana mod id.
    let records: [Int: ModRecord]
    @ObservedObject var gameBanana: GameBananaBandModel
    let focusedIndex: Int?
    let onFocus: (Int) -> Void
    let onOpen: (Int) -> Void

    /// Selene DetailsStage's band tiles, as the screenshot strip draws them in Details.
    private static let style = SpotlightScreenshotStrip.Style.details
    /// The decode size of a GameBanana mod's art on its tile (`GameBananaBandModel.prepareImages` decodes the
    /// same, so a group of mods shows with its art).
    static let thumbnailPixels = 600
    /// GameBanana's mods fade in as a group (`GameBananaBandModel` shows two at most).
    private static let arrival = Animation.easeOut(duration: 0.3)
    /// How much taller than one row of tiles the band is, for the pages that place the bands below it.
    static func extraHeight(tileCount: Int) -> CGFloat {
        CGFloat(max(ModsBandLayout.rows(count: tileCount) - 1, 0)) * (style.tileHeight + style.gap)
    }

    static func tiles(mods: [LocalMod], gameBanana: GameBananaBandModel) -> [ModsBandTile] {
        ModsBandLayout.tiles(installed: mods.count, available: gameBanana.available.map(\.id), status: gameBanana.statusTiles)
    }

    /// A tile and the identity it is drawn under: its own, or for a status tile also its place.
    private struct Placed: Identifiable {
        let tile: ModsBandTile
        let id: String
    }

    var body: some View {
        let tiles = Self.tiles(mods: mods, gameBanana: gameBanana).enumerated().map { index, tile -> Placed in
            if case .status = tile { return Placed(tile: tile, id: "\(tile)@\(index)") }
            return Placed(tile: tile, id: "\(tile)")
        }
        let style = Self.style
        let columns = ModsBandLayout.columns, rows = ModsBandLayout.rows(count: tiles.count)
        let pitchX = style.tileWidth + style.gap, pitchY = style.tileHeight + style.gap
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: canvas.u(18)) {
                DetailsBandTitle(text: title)
                if let line = gameBanana.statusLine {
                    Text(line)
                        .seleneFont(16, .medium)
                        .foregroundColor(SeleneTheme.ink60)
                }
                Spacer(minLength: 0)
                if gameBanana.phase != .idle {
                    Text("Mod data provided by GameBanana")
                        .seleneFont(14)
                        .foregroundColor(SeleneTheme.ink60)
                }
            }
            .frame(width: canvas.u(1700), alignment: .leading)
            // A grid six tiles to a row that never slides: Left/Right stay in the row, Down walks the rows. Each
            // tile keeps its identity as GameBanana's mods arrive, so nothing redraws under the focus; grow and
            // ring share the strip's one curve. Every tile is made at once at its own place: a lazy grid made
            // its tiles as the page glided in and moved each from a guessed place to its own, out of step.
            // GameBanana's mods come in groups and fade in together; a status tile pushed along by them fades out
            // and in at its new place instead of crossing the band.
            ZStack(alignment: .topLeading) {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, kind in
                    tileView(kind.tile, index: index, focused: focusedIndex == index)
                        .offset(x: canvas.u(CGFloat(index % columns) * pitchX),
                                y: canvas.u(CGFloat(index / columns) * pitchY))
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : Self.arrival, value: tiles.map(\.id))
            .frame(width: canvas.u(CGFloat(columns) * pitchX - style.gap),
                   height: canvas.u(CGFloat(max(rows, 1)) * pitchY - style.gap), alignment: .topLeading)
            .padding(.top, canvas.u(14))
            .animation(reduceMotion ? nil : SpotlightScreenshotStrip.motion, value: focusedIndex)
        }
    }

    private var title: String {
        let on = mods.filter(\.isOn).count
        return on == 0 ? "Mods" : "Mods · \(on) on"
    }

    static func state(_ mod: LocalMod) -> String { mod.romfs == nil ? "Not a mod" : mod.isOn ? "On" : "Off" }

    @ViewBuilder
    private func tileView(_ kind: ModsBandTile, index: Int, focused: Bool) -> some View {
        switch kind {
        case .installed(let i):
            let mod = mods[i]
            tile(index: index, focused: focused) { installedFace(mod) }
                .accessibilityLabel("\(mod.folderName), \(Self.state(mod))")
        case .manage:
            tile(index: index, focused: focused) { manageFace }
                .accessibilityLabel(mods.isEmpty ? "Add mods" : "Manage mods")
        case .available(let id):
            if let mod = gameBanana.available.first(where: { $0.id == id }) {
                tile(index: index, focused: focused, bleed: true) { availableFace(mod) }
                    .accessibilityLabel("\(mod.name), by \(mod.author)\(chip(for: mod).map { ", \($0)" } ?? "")")
            }
        case .status(let action):
            tile(index: index, focused: focused) { statusFace(action) }
                .accessibilityLabel(statusText(action).title)
        }
    }

    private func installedFace(_ mod: LocalMod) -> some View {
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
            Text(mods.isEmpty ? "File mods, no rebuild" : mods.count > ModsBandLayout.maxInstalled ? "All \(mods.count) mods" : "Order, folder, Remove")
                .seleneFont(15, .medium)
                .foregroundColor(SeleneTheme.ink60)
        }
    }

    /// Installed / Update / the install in progress, for an available mod.
    private func chip(for mod: AvailableMod) -> String? {
        switch gameBanana.installs[mod.id] {
        case .downloading(let fraction): return "Downloading \(Int(fraction * 100))%"
        case .installing: return "Installing…"
        case .failed: return "Didn't install"
        case .done, nil: break
        }
        guard let record = records[mod.id] else { return nil }
        return ModUpdateCheck.update(for: record, in: mod) == nil ? "Installed" : "Update"
    }

    private func availableFace(_ mod: AvailableMod) -> some View {
        ZStack(alignment: .bottomLeading) {
            GameBananaImageView(url: mod.thumbnailURL, maxPixelSize: Self.thumbnailPixels)
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: canvas.u(2)) {
                if let chip = chip(for: mod) {
                    Text(chip)
                        .seleneFont(13, .semibold)
                        .foregroundColor(SeleneTheme.ink)
                        .padding(.horizontal, canvas.u(10))
                        .padding(.vertical, canvas.u(4))
                        .background(Capsule().fill(SeleneTheme.glassSolid))
                        .padding(.bottom, canvas.u(4))
                }
                Text(mod.name)
                    .seleneFont(18, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(1)
                Text("by \(mod.author)")
                    .seleneFont(14, .medium)
                    .foregroundColor(SeleneTheme.ink75)
                    .lineLimit(1)
            }
            .padding(canvas.u(16))
        }
    }

    private func statusText(_ action: ModsBandAction) -> (icon: MaterialIcon, title: String, about: String) {
        switch action {
        case .retry: return (.sync, "Retry", "Ask GameBanana again")
        case .openPage: return (.link, "Open on GameBanana", "See every mod for this game")
        case .candidate(let id):
            return (.store, gameBanana.candidate(id)?.name ?? "Game", "This is the game")
        case .noneOfThese: return (.close, "None of these", "Pick the game by name")
        case .findGame: return (.search, "Find the game", "Search GameBanana by name")
        case .wrongGame: return (.search, "Wrong game?", gameBanana.matchedName.map { "GameBanana: \($0)" } ?? "Pick another game")
        }
    }

    private func statusFace(_ action: ModsBandAction) -> some View {
        let text = statusText(action)
        return VStack(alignment: .leading, spacing: canvas.u(8)) {
            MaterialIconView(text.icon, size: 26)
                .foregroundColor(SeleneTheme.ink75)
            Spacer(minLength: 0)
            Text(text.title)
                .seleneFont(19, .semibold)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(2)
            Text(text.about)
                .seleneFont(15, .medium)
                .foregroundColor(SeleneTheme.ink60)
                .lineLimit(1)
        }
    }

    /// A tile on glass, as the screenshot strip's: rasterised once so it slides as one layer, the focus ring 4
    /// outside it, and the grow on the strip's curve.
    private func tile<Face: View>(index: Int, focused: Bool, bleed: Bool = false, @ViewBuilder face: () -> Face) -> some View {
        let style = Self.style
        let w = canvas.u(style.tileWidth), h = canvas.u(style.tileHeight)
        let shape = RoundedRectangle(cornerRadius: canvas.u(style.radius), style: .continuous)
        return ZStack {
            shape.fill(SeleneTheme.glassSolid)
            face()
                .padding(bleed ? 0 : canvas.u(18))
                .frame(width: w, height: h, alignment: .topLeading)
                .clipShape(shape)
        }
        .frame(width: w, height: h)
        .drawingGroup()
        .overlay(
            RoundedRectangle(cornerRadius: canvas.u(style.radius + 3), style: .continuous)
                .strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(3))
                .padding(canvas.u(-4))
                .opacity(focused ? 1 : 0)
        )
        .scaleEffect(focused ? style.focusScale : 1)
        // The grown tile and its ring draw over the neighbours in the grid.
        .zIndex(focused ? 1 : 0)
        .animation(reduceMotion ? nil : SpotlightScreenshotStrip.motion, value: focused)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen(index) }
        .simultaneousGesture(TapGesture().onEnded { onFocus(index) })
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
    }
}

/// An image from GameBanana's CDN, through the shared cache; empty glass until it arrives.
struct GameBananaImageView: View {
    let url: URL?
    var maxPixelSize: Int = 800
    var contentMode: ContentMode = .fill
    @State private var image: NSImage?

    /// Decoded images stay in memory (about 160 MB at most), so a tile that comes back into view, or the same art
    /// in another row, shows at once instead of decoding again.
    private static let decoded: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 160 * 1024 * 1024
        return cache
    }()

    private static func key(_ url: URL, _ size: Int) -> NSString { "\(size)|\(url.absoluteString)" as NSString }

    /// Decodes art before a view asks for it (the store's next rows), at low priority.
    static func prewarm(_ urls: [URL], maxPixelSize: Int) {
        let missing = urls.filter { decoded.object(forKey: key($0, maxPixelSize)) == nil }
        guard !missing.isEmpty else { return }
        Task(priority: .utility) {
            for url in missing where decoded.object(forKey: key(url, maxPixelSize)) == nil {
                guard let file = await GameBananaServices.shared.images.file(for: url),
                      let image = await GameArtLoader.decode(at: file, maxPixelSize: maxPixelSize) else { continue }
                store(image, for: key(url, maxPixelSize))
            }
        }
    }

    /// Decodes `urls` now, side by side (the image cache limits the downloads), and returns once each is ready or
    /// could not be read, so a view that shows them all at once never shows one arriving after the others.
    static func prepare(_ urls: [URL], maxPixelSize: Int) async {
        let missing = urls.filter { decoded.object(forKey: key($0, maxPixelSize)) == nil }
        guard !missing.isEmpty else { return }
        let images = GameBananaServices.shared.images
        await withTaskGroup(of: (URL, NSImage)?.self) { group in
            for url in missing {
                group.addTask {
                    guard let file = await images.file(for: url),
                          let image = await GameArtLoader.decode(at: file, maxPixelSize: maxPixelSize) else { return nil }
                    return (url, image)
                }
            }
            for await result in group {
                if let (url, image) = result { store(image, for: key(url, maxPixelSize)) }
            }
        }
    }

    private static func store(_ image: NSImage, for key: NSString) {
        let pixels = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh } ?? 0
        decoded.setObject(image, forKey: key, cost: max(pixels, 1) * 4)
    }

    init(url: URL?, maxPixelSize: Int = 800, contentMode: ContentMode = .fill) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        _image = State(initialValue: url.flatMap { Self.decoded.object(forKey: Self.key($0, maxPixelSize)) })
    }

    var body: some View {
        ZStack {
            SeleneTheme.glassSolid
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: url) {
            guard let url else { image = nil; return }
            let key = Self.key(url, maxPixelSize)
            if let cached = Self.decoded.object(forKey: key) {
                if image !== cached { image = cached }
                return
            }
            image = nil
            guard let file = await GameBananaServices.shared.images.file(for: url),
                  let decoded = await GameArtLoader.decode(at: file, maxPixelSize: maxPixelSize),
                  !Task.isCancelled else { return }
            Self.store(decoded, for: key)
            withAnimation(.easeOut(duration: 0.25)) { image = decoded }
        }
    }
}
