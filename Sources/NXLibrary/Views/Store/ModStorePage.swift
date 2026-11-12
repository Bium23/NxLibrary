import SwiftUI
import NXLibraryCore

/// The mod store under the Mods card, top to bottom: the sort bar, Featured, the mods across your games, a row per
/// category, a row per game, then GameBanana's credit. Every section has a fixed height (`ModStoreLayout`), so the
/// page scrolls without measuring, and only the sections near the focus are drawn: the rest keep their height and
/// draw nothing, so a long store moves as lightly as a short one.
struct ModStorePage: View {
    @Environment(\.seleneCanvas) private var canvas

    @ObservedObject var host: ModStoreHost
    @ObservedObject var catalog: ModStoreModel
    /// The page has the focus (not the row above it).
    let active: Bool

    /// Sections drawn around the focused one: enough to fill the screen and start the next rows' images early.
    private static let drawnAbove = 2
    private static let drawnBelow = 4

    var body: some View {
        let sections = host.sections
        let at = active ? host.focus.position(in: host.focusSections) : 0
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.kind) { index, section in
                Group {
                    if index >= at - Self.drawnAbove, index <= at + Self.drawnBelow {
                        sectionView(section, focused: active && host.focus.kind == section.kind)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: canvas.u(1700), height: canvas.u(ModStoreLayout.height(section.kind)), alignment: .topLeading)
            }
            footer
        }
    }

    @ViewBuilder
    private func sectionView(_ section: ModStoreSection, focused: Bool) -> some View {
        switch section.kind {
        case .sort:
            ModStoreSortBar(sort: host.sort, focusedIndex: focused ? host.focus.index : nil,
                            onPick: { host.activate(.sort, $0) })
        case .featured:
            ModStoreFeatured(entries: section.entries, index: host.focus.index(of: .featured), focused: focused,
                             chip: { ModStoreChip(entry: $0, host: host, installs: host.panel.gameBanana) },
                             onOpen: { host.activate(.featured, host.focus.index(of: .featured)) })
        case .popular, .category, .game:
            ModStoreRow(section: section, showsGame: !isGameRow(section.kind),
                        focusedIndex: focused ? host.focus.index : nil,
                        scrollIndex: host.focus.index(of: section.kind),
                        host: host,
                        onFocus: { host.pointerFocus(section.kind, $0) },
                        onOpen: { host.activate(section.kind, $0) })
        }
    }

    private func isGameRow(_ kind: ModStoreSectionKind) -> Bool {
        if case .game = kind { return true }
        return false
    }

    /// Where the store stands, then GameBanana's credit.
    private var footer: some View {
        VStack(alignment: .leading, spacing: canvas.u(10)) {
            if let line = statusLine {
                HStack(spacing: canvas.u(12)) {
                    if catalog.refreshing { ProgressView().controlSize(.small).tint(SeleneTheme.ink60) }
                    Text(line).seleneFont(18, .medium).foregroundColor(SeleneTheme.ink75)
                }
            }
            Text(L10n.text("Mod data provided by GameBanana · only mods that work with NX Library are shown"))
                .seleneFont(14)
                .foregroundColor(SeleneTheme.ink60)
        }
        .frame(width: canvas.u(1700), alignment: .leading)
        .padding(.top, canvas.u(8))
    }

    private var statusLine: String? {
        switch catalog.phase {
        case .offline: return L10n.text("No connection. Mods you installed still work.")
        case .loading: return L10n.text("Looking for mods that work with your games…")
        case .idle: return nil
        case .ready:
            if catalog.games.isEmpty {
                return catalog.refreshing ? L10n.text("Looking for mods that work with your games…")
                    : L10n.text("No mods for your games work with NX Library yet.")
            }
            return catalog.refreshing ? L10n.text("Looking for more mods…") : nil
        }
    }
}

// MARK: - Sort bar

/// Popular, Most liked, Newest, Recently updated: the chosen one is filled, the focused one ringed.
struct ModStoreSortBar: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let sort: ModStoreSort
    let focusedIndex: Int?
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: canvas.u(14)) {
            ForEach(Array(ModStoreSort.allCases.enumerated()), id: \.element) { index, choice in
                let chosen = choice == sort
                let focused = focusedIndex == index
                HStack(alignment: .firstTextBaseline, spacing: canvas.u(10)) {
                    MaterialIconView(choice.icon, size: 22).iconOnCaps(of: 18, .semibold)
                    Text(choice.title).seleneFont(18, .semibold)
                }
                .foregroundColor(chosen ? SeleneTheme.onFocus : SeleneTheme.ink)
                .padding(.horizontal, canvas.u(22))
                .frame(height: canvas.u(52))
                .background(Capsule().fill(chosen ? SeleneTheme.focus : SeleneTheme.glass))
                .overlay(Capsule().inset(by: canvas.u(-4)).strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(3))
                    .opacity(focused ? 1 : 0))
                .scaleEffect(focused ? 1.04 : 1)
                .animation(reduceMotion ? nil : SpotlightScreenshotStrip.motion, value: focused)
                .animation(reduceMotion ? nil : SpotlightScreenshotStrip.motion, value: chosen)
                .contentShape(Capsule())
                .onTapGesture { onPick(index) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.format("Sort by %@", [String(describing: (choice.title))]))
                .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.top, canvas.u(10))
    }
}

// MARK: - Featured

/// One large banner: the mod's art blurred across it, the art itself on the right, its name, game and numbers on
/// the left. Left/Right crossfades to the next of the top five (no sliding); dots say where you are.
struct ModStoreFeatured<Chip: View>: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let entries: [ModCatalogEntry]
    let index: Int
    let focused: Bool
    @ViewBuilder let chip: (ModCatalogEntry) -> Chip
    let onOpen: () -> Void

    var body: some View {
        let entry = entries.indices.contains(index) ? entries[index] : entries.first
        let shape = RoundedRectangle(cornerRadius: canvas.u(24), style: .continuous)
        return ZStack {
            if let entry {
                slide(entry)
                    .id(entry.id)
                    .transition(.opacity)
            }
        }
        .frame(width: canvas.u(1700), height: canvas.u(420))
        .clipShape(shape)
        .overlay(shape.inset(by: canvas.u(-5)).strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(3))
            .opacity(focused ? 1 : 0))
        .scaleEffect(focused ? 1.01 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: entry?.id)
        .animation(reduceMotion ? nil : SpotlightScreenshotStrip.motion, value: focused)
        .contentShape(shape)
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.map { L10n.format("Featured: %@, for %@, by %@", [String(describing: ($0.mod.name)), String(describing: ($0.gameName)), String(describing: ($0.mod.author))]) } ?? L10n.text("Featured"))
        .accessibilityAddTraits(.isButton)
    }

    private func slide(_ entry: ModCatalogEntry) -> some View {
        let art = entry.mod.images.first ?? entry.mod.thumbnailURL
        return ZStack(alignment: .leading) {
            // The art, blurred once off the main thread and kept, as the banner's ground: no blur runs per frame.
            Color.black.opacity(0.35)
            GameBananaBlurView(url: art)
                .frame(width: canvas.u(1700), height: canvas.u(420))
            LinearGradient(colors: [.black.opacity(0.78), .black.opacity(0.45), .black.opacity(0.15)],
                           startPoint: .leading, endPoint: .trailing)
            HStack(alignment: .center, spacing: canvas.u(48)) {
                VStack(alignment: .leading, spacing: canvas.u(12)) {
                    Text(L10n.format("FEATURED · %@", [String(describing: (entry.gameName.uppercased()))]))
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.ink75)
                        .lineLimit(1)
                    Text(entry.mod.name)
                        .seleneFont(46, .semibold)
                        .foregroundColor(SeleneTheme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.format("by %@", [String(describing: (entry.mod.author))]))
                        .seleneFont(19, .medium)
                        .foregroundColor(SeleneTheme.ink82)
                    HStack(spacing: canvas.u(22)) {
                        stat(.thumbUp, "\(entry.mod.likes)")
                        stat(.download, "\(entry.mod.downloads)")
                        Text(entry.category.title).seleneFont(16, .medium).foregroundColor(SeleneTheme.ink75)
                    }
                    .padding(.top, canvas.u(4))
                    HStack(spacing: canvas.u(14)) {
                        chip(entry)
                        HStack(spacing: canvas.u(8)) {
                            SelenePromptBadge(button: .a)
                            Text(L10n.text("View")).seleneFont(18).foregroundColor(SeleneTheme.ink90)
                        }
                    }
                    .padding(.top, canvas.u(10))
                }
                .frame(width: canvas.u(860), alignment: .leading)
                Spacer(minLength: 0)
                GameBananaImageView(url: art, maxPixelSize: 700)
                    .frame(width: canvas.u(620), height: canvas.u(349))
                    .clipShape(RoundedRectangle(cornerRadius: canvas.u(18), style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: canvas.u(18), y: canvas.u(8))
            }
            .padding(.horizontal, canvas.u(56))
            dots
        }
        .drawingGroup()
    }

    private var dots: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: canvas.u(8)) {
                ForEach(entries.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? SeleneTheme.ink : SeleneTheme.ink25)
                        .frame(width: canvas.u(i == index ? 26 : 8), height: canvas.u(8))
                }
            }
            .padding(.bottom, canvas.u(22))
            .padding(.leading, canvas.u(56))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ icon: MaterialIcon, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: canvas.u(6)) {
            MaterialIconView(icon, size: 18).iconOnCaps(of: 16, .semibold)
            Text(value).seleneFont(16, .semibold)
        }
        .foregroundColor(SeleneTheme.ink82)
    }
}

// MARK: - Rows

/// A titled row of mod tiles (336 × 189) that slides only as far as the focused tile needs, on the screenshot
/// strip's one curve. A small chevron right of the row says tiles are hidden past its edge.
struct ModStoreRow: View {
    /// A row's title, a little larger than a game page band's (21).
    static let titleSize: CGFloat = 24

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let section: ModStoreSection
    /// Tiles say which game they are for, except in the game's own row.
    let showsGame: Bool
    let focusedIndex: Int?
    let scrollIndex: Int
    let host: ModStoreHost
    let onFocus: (Int) -> Void
    let onOpen: (Int) -> Void

    var body: some View {
        let scroll = ModStoreLayout.rowScroll(index: focusedIndex ?? scrollIndex)
        let more = ModStoreLayout.moreToTheRight(count: section.entries.count, index: focusedIndex ?? scrollIndex)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: canvas.u(14)) {
                if case .category(let category) = section.kind {
                    MaterialIconView(category.icon, size: 25).foregroundColor(SeleneTheme.ink75)
                        .iconOnCaps(of: Self.titleSize, .semibold)
                }
                DetailsBandTitle(text: section.title, size: Self.titleSize)
                Text(section.entries.count == 1 ? L10n.text("1 mod") : L10n.format("%@ mods", [String(describing: (section.entries.count))]))
                    .seleneFont(16, .medium)
                    .foregroundColor(SeleneTheme.ink60)
            }
            HStack(alignment: .top, spacing: canvas.u(ModStoreLayout.gap)) {
                ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                    ModStoreTile(entry: entry, showsGame: showsGame, focused: focusedIndex == index,
                                 chip: ModStoreChip(entry: entry, host: host, installs: host.panel.gameBanana))
                        .onTapGesture(count: 2) { onOpen(index) }
                        .simultaneousGesture(TapGesture().onEnded { onFocus(index) })
                }
            }
            .padding(canvas.u(14))
            .offset(x: -canvas.u(scroll))
            .frame(width: canvas.u(ModStoreLayout.clipWidth), alignment: .leading)
            .clipped()
            .padding(canvas.u(-14))
            .animation(reduceMotion ? nil : SpotlightScreenshotStrip.motion, value: focusedIndex ?? scrollIndex)
            // Past the clip's right edge, in the margin: more tiles that way.
            .overlay(alignment: .trailing) {
                SpotlightRightHint()
                    .offset(x: canvas.u(40))
                    .opacity(more ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: more)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// A mod's tile: its art, the name and the game (or author) over a dark fade, the Installed/Update chip.
struct ModStoreTile: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let entry: ModCatalogEntry
    let showsGame: Bool
    let focused: Bool
    let chip: ModStoreChip

    var body: some View {
        let w = canvas.u(ModStoreLayout.tileWidth), h = canvas.u(ModStoreLayout.tileHeight)
        let shape = RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            shape.fill(SeleneTheme.glassSolid)
            GameBananaImageView(url: entry.mod.images.first ?? entry.mod.thumbnailURL, maxPixelSize: 700)
            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: canvas.u(2)) {
                chip.padding(.bottom, canvas.u(4))
                Text(entry.mod.name)
                    .seleneFont(19, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(1)
                Text(showsGame ? entry.gameName : L10n.format("by %@", [String(describing: (entry.mod.author))]))
                    .seleneFont(14, .medium)
                    .foregroundColor(SeleneTheme.ink75)
                    .lineLimit(1)
            }
            .padding(canvas.u(16))
        }
        .frame(width: w, height: h)
        .clipShape(shape)
        // Rasterised once and moved as one layer as the row slides.
        .drawingGroup()
        .overlay(RoundedRectangle(cornerRadius: canvas.u(17), style: .continuous)
            .strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(3))
            .padding(canvas.u(-4))
            .opacity(focused ? 1 : 0))
        .scaleEffect(focused ? 1.05 : 1)
        .zIndex(focused ? 1 : 0)
        .animation(reduceMotion ? nil : SpotlightScreenshotStrip.motion, value: focused)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("%@, for %@, by %@", [String(describing: (entry.mod.name)), String(describing: (entry.gameName)), String(describing: (entry.mod.author))]))
        .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
    }
}

/// Installed / Update / download progress. It watches the installs by itself, so a download's progress redraws
/// only its chips, not the page.
struct ModStoreChip: View {
    @Environment(\.seleneCanvas) private var canvas

    let entry: ModCatalogEntry
    let host: ModStoreHost
    @ObservedObject var installs: GameBananaBandModel

    var body: some View {
        if let text = host.chip(for: entry) {
            Text(text)
                .seleneFont(13, .semibold)
                .foregroundColor(SeleneTheme.ink)
                .padding(.horizontal, canvas.u(10))
                .padding(.vertical, canvas.u(4))
                .background(Capsule().fill(SeleneTheme.glassSolid))
        }
    }
}
