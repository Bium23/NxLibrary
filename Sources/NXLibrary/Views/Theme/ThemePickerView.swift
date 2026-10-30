import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

/// The menu's Theme screen (Selene's ProfileSteps from Theme): first the theme's
/// colors, then the background, each beside a preview of the home. A on a theme
/// applies it and goes on; A on a background applies it and closes the menu. B
/// steps back (from the colors: to the menu). The background step has two tabs,
/// Wallpapers and Live, switched with LB/RB (Q/E); it adds your own pictures or
/// videos (copied into NX Library) and removes them again with Y (Delete). An
/// online source's tile opens its grid: chips of categories, a search, and A
/// downloads the full picture (B cancels) before applying it.
struct ThemePickerView: View {
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: AppSettingsStore
    /// The library, for the preview's tiles.
    let games: [PortedGame]

    @ObservedObject private var theme = ThemeStore.shared
    @State private var state = ThemePickerState(themeIndex: 0, backgroundIndex: 0)
    @State private var opened = false
    @State private var importError: String?
    @State private var errorTitle = "Couldn't add the picture"
    @StateObject private var browser = OnlineBrowser()
    @StateObject private var transfer = OnlineTransfer()
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    private var palettes: [SelenePalette] { theme.palettes.isEmpty ? [theme.palette] : theme.palettes }
    private var backgrounds: [ThemeBackgroundChoice] {
        ThemeBackgrounds.list(state.tab, themeID: theme.palette.id, wallpapers: theme.wallpapers)
    }
    private var focusedBackground: ThemeBackgroundChoice {
        let list = backgrounds
        return list[min(state.backgroundIndex, list.count - 1)]
    }

    var body: some View {
        ZStack(alignment: .top) {
            SeleneBackdrop()
            Color.black.opacity(0.3).ignoresSafeArea()

            Group {
                switch state.step {
                case .theme: themeStep.transition(stepTransition(forward: false))
                case .background: backgroundStep.transition(stepTransition(forward: true))
                }
            }
            .animation(reduceMotion ? nil : SeleneTheme.screen, value: state.step)

            dots
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, canvas.u(124))

            SeleneHintsBar(left: [HintItem(.b, transfer.itemID != nil ? "Cancel" : "Back", action: back)], right: rightHints,
                           bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear(perform: open)
        .onReceive(NotificationCenter.default.publisher(for: .nxThemePickerGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handle(action)
        }
        .alert(errorTitle, isPresented: Binding(get: { importError != nil },
                                                                set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func stepTransition(forward: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let offset = canvas.u(70)
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: forward ? offset : -offset)),
                           removal: .opacity.combined(with: .offset(x: forward ? offset : -offset)))
    }

    private var rightHints: [HintItem] {
        switch state.step {
        case .theme:
            return [HintItem(.a, "Next", action: accept)]
        case .background:
            if let browse = browser.state {
                guard transfer.itemID == nil else { return [] }
                if let item = browse.focusedItem {
                    let have = theme.wallpapers.contains { $0.id == OnlineDownload.wallpaperID(for: item) }
                    return [HintItem(.x, "Open page", action: { NSWorkspace.shared.open(item.pageURL) }),
                            HintItem(.a, have ? "Done" : "Download", action: accept)]
                }
                return browse.category.isSearch ? [HintItem(.a, "Search", action: accept)] : []
            }
            var hints: [HintItem] = []
            if case .wallpaper(let id) = focusedBackground, let credit = theme.credits[id] {
                hints.append(HintItem(.x, "Open page", action: { NSWorkspace.shared.open(credit.pageURL) }))
            }
            if case .wallpaper(let id) = focusedBackground, ThemeStore.isRemovable(id) {
                hints.append(HintItem(.y, "Remove", action: removeFocused))
            }
            let verb: String
            switch focusedBackground {
            case .add: verb = "Add"
            case .online: verb = "Browse"
            default: verb = "Done"
            }
            hints.append(HintItem(.a, verb, action: accept))
            return hints
        }
    }

    private var dots: some View {
        HStack(spacing: canvas.u(10)) {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .fill(SeleneTheme.ink.opacity((index == 0) == (state.step == .theme) ? 1 : 0.3))
                    .frame(width: canvas.u(8), height: canvas.u(8))
            }
        }
    }

    private func header(_ title: String, _ sub: String) -> some View {
        VStack(spacing: canvas.u(10)) {
            Text(title).seleneFont(44).foregroundColor(SeleneTheme.ink)
            Text(sub).seleneFont(21).foregroundColor(SeleneTheme.ink.opacity(0.7))
        }
        .multilineTextAlignment(.center)
        .padding(.top, canvas.u(110))
    }

    // MARK: - Theme step

    private var themeStep: some View {
        let palette = palettes[min(state.themeIndex, palettes.count - 1)]
        return ZStack(alignment: .top) {
            header("Choose your theme", "Colors for all of NX Library. Move through them to see each one in the preview.")
            HStack(alignment: .top, spacing: canvas.u(60)) {
                grid(count: palettes.count, columns: ThemePickerState.themeColumns) { index in
                    swatch(palettes[index], focused: index == state.themeIndex)
                        .onTapGesture { tap(index) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ThemePreview(palette: palette, wallpaperURL: previewWallpaper(theme: palette),
                                 games: games, width: 780)
                    chips(palette)
                        .padding(.top, canvas.u(18))
                        .padding(.leading, canvas.u(4))
                    Text(palette.name + (palette.mode == .light ? "  ·  light" : ""))
                        .seleneFont(26)
                        .foregroundColor(SeleneTheme.ink)
                        .padding(.top, canvas.u(12))
                        .padding(.leading, canvas.u(4))
                }
            }
            .padding(.top, canvas.u(290))
        }
    }

    private func swatch(_ palette: SelenePalette, focused: Bool) -> some View {
        let background = Color(hex: palette.base.stops.first?.color ?? palette.glass)
        let shape = RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
        return VStack(spacing: canvas.u(8)) {
            ZStack {
                background
                if let url = WallpaperCatalog.resolve(nil, themeID: palette.id, in: theme.wallpapers)?.url {
                    WallpaperThumb(url: url)
                }
                // The theme's color fades in from the left so "Aa" reads on any wallpaper.
                LinearGradient(stops: [.init(color: background.opacity(0.9), location: 0),
                                       .init(color: background.opacity(0.33), location: 0.55),
                                       .init(color: background.opacity(0), location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                HStack {
                    Text("Aa").seleneFont(22).foregroundColor(Color(hex: palette.ink))
                    Spacer(minLength: 0)
                    Circle()
                        .fill(Color(hex: palette.glyph))
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
                        .frame(width: canvas.u(20), height: canvas.u(20))
                }
                .padding(.horizontal, canvas.u(12))
            }
            .frame(width: canvas.u(132), height: canvas.u(76))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .modifier(TileFocus(focused: focused, radius: 14, scale: 1.08))
            Text(palette.name)
                .seleneFont(14)
                .foregroundColor(SeleneTheme.ink75)
                .lineLimit(1)
                .frame(maxWidth: canvas.u(140))
        }
        .padding(.horizontal, canvas.u(9))
        .padding(.top, canvas.u(6))
        .padding(.bottom, canvas.u(8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(palette.name)
        .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
    }

    /// The palette's colors as a strip of chips.
    private func chips(_ palette: SelenePalette) -> some View {
        var colors: [UInt32] = []
        for color in palette.base.stops.map(\.color) + [palette.glass, palette.ink, palette.focus, palette.glyph, palette.success]
        where !colors.contains(color) {
            colors.append(color)
        }
        return HStack(spacing: canvas.u(8)) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: canvas.u(8), style: .continuous)
                    .fill(Color(hex: color))
                    .overlay(RoundedRectangle(cornerRadius: canvas.u(8), style: .continuous)
                        .strokeBorder(SeleneTheme.ink25, lineWidth: 1))
                    .frame(width: canvas.u(46), height: canvas.u(26))
            }
        }
        .id(palette.id)
        .transition(.opacity)
    }

    /// The theme's own wallpaper unless one was picked (as Selene shows it).
    private func previewWallpaper(theme palette: SelenePalette) -> URL? {
        switch settings.settings.wallpaperID {
        case nil: return WallpaperCatalog.resolve(nil, themeID: palette.id, in: theme.wallpapers)?.url
        case let id?: return theme.wallpaper(for: id)?.url
        }
    }

    // MARK: - Background step

    private var backgroundStep: some View {
        let list = backgrounds
        let focused = focusedBackground
        return ZStack(alignment: .top) {
            if let browse = browser.state {
                header(browse.source.title, Self.about(browse.source))
            } else {
                header("Choose your background", "Behind the menus and the home when no game is selected.")
            }
            HStack(alignment: .top, spacing: canvas.u(50)) {
                if let browse = browser.state {
                    OnlineBrowsePanel(state: browse, loading: browser.loading, failed: browser.failed,
                                      downloadingID: transfer.itemID, progress: transfer.progress,
                                      downloaded: Set(theme.wallpapers.map(\.id)),
                                      searchText: $searchText, searchFocused: $searchFocused,
                                      onSubmit: submitSearch, onChip: tapChip, onTile: tapTile)
                } else {
                VStack(alignment: .leading, spacing: 0) {
                    tabs
                        .padding(.bottom, canvas.u(18))
                    Text(ThemeBackgrounds.group(focused, tab: state.tab))
                        .seleneFont(13, .semibold)
                        .foregroundColor(SeleneTheme.ink.opacity(0.55))
                        .padding(.leading, canvas.u(10))
                        .padding(.bottom, canvas.u(10))
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            grid(count: list.count, columns: ThemePickerState.backgroundColumns) { index in
                                backgroundTile(list[index], focused: index == state.backgroundIndex)
                                    .id(index)
                                    .onTapGesture { tap(index) }
                            }
                            .padding(.vertical, canvas.u(10))
                        }
                        .scrollIndicators(.hidden)
                        .frame(width: canvas.u(3 * 226), height: canvas.u(500))
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                                     .init(color: .black, location: 1 - 150 / 500),
                                                     .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                        .onChange(of: state.backgroundIndex) { index in
                            withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                                proxy.scrollTo(index - index % ThemePickerState.backgroundColumns, anchor: .center)
                            }
                        }
                    }
                }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ThemePreview(palette: theme.palette, wallpaperURL: previewURL(focused), games: games, width: 820)
                    Text(creditLine(focused) ?? " ")
                        .seleneFont(17)
                        .foregroundColor(SeleneTheme.ink75)
                        .lineLimit(1)
                        .padding(.top, canvas.u(16))
                        .padding(.leading, canvas.u(4))
                }
            }
            .padding(.top, canvas.u(250))
        }
    }

    /// Wallpapers | Live, between the shoulder badges, as on the home.
    private var tabs: some View {
        HStack(spacing: canvas.u(8)) {
            SelenePromptBadge(button: .lb, height: 26).accessibilityHidden(true)
            ForEach(BackgroundTab.allCases, id: \.self) { tab in
                Text(tab == .wallpapers ? "Wallpapers" : "Live")
                    .seleneFont(17, .semibold)
                    .foregroundColor(tab == state.tab ? SeleneTheme.ink : SeleneTheme.ink60)
                    .padding(.horizontal, canvas.u(20))
                    .padding(.vertical, canvas.u(9))
                    .background(Capsule().fill(tab == state.tab ? SeleneTheme.glassSolid : Color.clear))
                    .contentShape(Capsule())
                    .onTapGesture { switchTab(to: tab) }
                    .accessibilityAddTraits(tab == state.tab ? [.isButton, .isSelected] : .isButton)
            }
            SelenePromptBadge(button: .rb, height: 26).accessibilityHidden(true)
        }
        .padding(.leading, canvas.u(6))
    }

    /// The line under a source's name while browsing it.
    static func about(_ source: BackgroundSourceID) -> String {
        switch source {
        case .wallhaven: return "Safe for work, 2K and up. Every picture belongs to its owner."
        case .danbooru: return "General rating only, 2K and up. Every picture belongs to its artist."
        case .motionbgs: return "Looping live wallpapers in 4K and HD. Every video belongs to its owner."
        case .steam: return "Animated profile backgrounds, made by the games' studios for Steam."
        }
    }

    /// The focused online item's thumbnail while browsing, else the focused tile's wallpaper.
    private func previewURL(_ choice: ThemeBackgroundChoice) -> URL? {
        if let browse = browser.state {
            return browse.focusedItem?.thumbnailURL ?? theme.wallpaper(for: settings.settings.wallpaperID)?.url
        }
        return wallpaperURL(choice)
    }

    /// Under the preview: the online item, or a download's credit.
    private func creditLine(_ choice: ThemeBackgroundChoice) -> String? {
        if let browse = browser.state {
            guard let item = browse.focusedItem else { return nil }
            var parts = [item.source.title, item.title]
            if let author = item.author { parts.append("art by \(author)") }
            parts.append("\(item.width) × \(item.height)")
            return parts.joined(separator: " · ")
        }
        if case .wallpaper(let id) = choice, let credit = theme.credits[id] { return credit.line }
        return nil
    }

    private func wallpaperURL(_ choice: ThemeBackgroundChoice) -> URL? {
        switch choice {
        case .theme: return theme.wallpaper(for: nil)?.url
        case .none: return nil
        case .add: return theme.wallpaper(for: settings.settings.wallpaperID)?.url
        case .wallpaper(let id): return theme.wallpaper(for: id)?.url
        case .online: return theme.wallpaper(for: settings.settings.wallpaperID)?.url
        }
    }

    private func backgroundTile(_ choice: ThemeBackgroundChoice, focused: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(12), style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            Rectangle().fill(SeleneTheme.baseGradient)
            switch choice {
            case .theme:
                if let url = theme.wallpaper(for: nil)?.url { WallpaperThumb(url: url) }
                tileLabel("Theme's own")
            case .none:
                if state.tab == .live {
                    MoonlightBackdrop(accent: SeleneTheme.glyph, ink: SeleneTheme.ink, moving: false, asImage: true)
                }
                tileLabel(state.tab == .live ? "Moonlight" : "None")
            case .add:
                SeleneTheme.glassSolid
                VStack(spacing: canvas.u(6)) {
                    MaterialIconView(.add, size: 34).foregroundColor(SeleneTheme.ink)
                    Text(state.tab == .live ? "Add your video…" : "Add your own…").seleneFont(15).foregroundColor(SeleneTheme.ink90)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .wallpaper(let id):
                if let url = theme.wallpaper(for: id)?.url { WallpaperThumb(url: url) }
                if state.tab == .live {
                    MaterialIconView(.play, size: 22)
                        .foregroundColor(.white)
                        .padding(canvas.u(8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .shadow(color: .black.opacity(0.6), radius: canvas.u(4))
                }
            case .online(let source):
                sourceTile(source)
            }
        }
        .frame(width: canvas.u(204), height: canvas.u(115))
        .clipShape(shape)
        .overlay(shape.strokeBorder(SeleneTheme.ink15, lineWidth: 1))
        .modifier(TileFocus(focused: focused, radius: 12, scale: 1.06))
        .padding(.horizontal, canvas.u(11))
        .padding(.top, canvas.u(13))
        .padding(.bottom, canvas.u(14))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(choice))
        .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
    }

    private func sourceTile(_ source: BackgroundSourceID) -> some View {
        ZStack {
            SeleneTheme.glassSolid
            VStack(spacing: canvas.u(6)) {
                MaterialIconView(.language, size: 30).foregroundColor(SeleneTheme.ink)
                Text(source.title).seleneFont(18, .semibold).foregroundColor(SeleneTheme.ink)
                Text("Browse online").seleneFont(13).foregroundColor(SeleneTheme.ink60)
            }
        }
    }

    private func tileLabel(_ text: String) -> some View {
        Text(text)
            .seleneFont(15)
            .foregroundColor(.white)
            .padding(.horizontal, canvas.u(10))
            .padding(.top, canvas.u(5))
            .padding(.bottom, canvas.u(6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.6))
    }

    private func label(_ choice: ThemeBackgroundChoice) -> String {
        switch choice {
        case .theme: return "Theme's own"
        case .none: return state.tab == .live ? "Moonlight" : "None"
        case .add: return state.tab == .live ? "Add your video" : "Add your own"
        case .wallpaper(let id): return theme.wallpaperTitle(for: id)
        case .online(let source): return "Browse \(source.title)"
        }
    }

    // MARK: - Grid

    private func grid<Cell: View>(count: Int, columns: Int, @ViewBuilder cell: @escaping (Int) -> Cell) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stride(from: 0, to: count, by: columns)), id: \.self) { first in
                HStack(spacing: 0) {
                    ForEach(first..<min(first + columns, count), id: \.self) { index in
                        cell(index)
                    }
                }
            }
        }
    }

    // MARK: - Input

    private func open() {
        guard !opened else { return }
        opened = true
        let themeIndex = palettes.firstIndex { $0.id == settings.settings.colorThemeID } ?? 0
        state = ThemePickerState(themeIndex: themeIndex, backgroundIndex: 0)
        focusSetting(themeID: theme.palette.id)
    }

    /// Opens the tab that holds the current setting, on its tile.
    private func focusSetting(themeID: String) {
        let id = settings.settings.wallpaperID
        state.tab = ThemeBackgrounds.tab(for: id, wallpapers: theme.wallpapers)
        state.backgroundIndex = ThemeBackgrounds.index(
            of: id, in: ThemeBackgrounds.list(state.tab, themeID: themeID, wallpapers: theme.wallpapers))
    }

    private func switchTab(to tab: BackgroundTab) {
        if state.switchTab(to: tab) { SoundEffectService.shared.play(.focus) }
    }

    private func stepTab(_ offset: Int) {
        let tabs = BackgroundTab.allCases
        guard let current = tabs.firstIndex(of: state.tab) else { return }
        let next = current + offset
        guard tabs.indices.contains(next) else { return }
        switchTab(to: tabs[next])
    }

    private func handle(_ action: GamepadAction) {
        if state.step == .background, browser.state != nil { return handleBrowse(action) }
        switch action {
        case .navigateUp: move(.up)
        case .navigateDown: move(.down)
        case .navigateLeft: move(.left)
        case .navigateRight: move(.right)
        case .confirm: accept()
        case .cancel: back()
        case .contextAction: removeFocused()
        case .secondaryAction:
            if case .wallpaper(let id) = focusedBackground, let credit = theme.credits[id] {
                NSWorkspace.shared.open(credit.pageURL)
            }
        case .tabPrevious: stepTab(-1)
        case .tabNext: stepTab(1)
        default: break
        }
    }

    private func move(_ direction: GridDirection) {
        let count = state.step == .theme ? palettes.count : backgrounds.count
        if state.move(direction, count: count) { SoundEffectService.shared.play(.focus) }
    }

    /// A click focuses a tile; a click on the focused one chooses it.
    private func tap(_ index: Int) {
        switch state.step {
        case .theme:
            if index == state.themeIndex { return accept() }
            state.themeIndex = index
        case .background:
            if index == state.backgroundIndex { return accept() }
            state.backgroundIndex = index
        }
        SoundEffectService.shared.play(.focus)
    }

    private func accept() {
        switch state.step {
        case .theme:
            let palette = palettes[min(state.themeIndex, palettes.count - 1)]
            settings.settings.colorThemeID = palette.id
            theme.apply(id: palette.id)
            focusSetting(themeID: palette.id)
            state.step = .background
            SoundEffectService.shared.play(.click)
        case .background:
            if let browse = browser.state {
                if let item = browse.focusedItem {
                    choose(item)
                } else if browse.category.isSearch {
                    searchFocused = true
                }
                return
            }
            switch focusedBackground {
            case .add:
                addOwn()
                return
            case .theme: settings.settings.wallpaperID = nil
            case .none: settings.settings.wallpaperID = WallpaperCatalog.none
            case .wallpaper(let id): settings.settings.wallpaperID = id
            case .online(let source):
                openSource(source)
                return
            }
            SoundEffectService.shared.play(.click)
            router.closeMenu()
        }
    }

    // MARK: - Online

    private func openSource(_ source: BackgroundSourceID) {
        searchText = ""
        browser.open(source)
        SoundEffectService.shared.play(.click)
    }

    private func handleBrowse(_ action: GamepadAction) {
        if transfer.itemID != nil {
            if action == .cancel { back() }
            return
        }
        switch action {
        case .navigateUp: browseMove(.up)
        case .navigateDown: browseMove(.down)
        case .navigateLeft: browseMove(.left)
        case .navigateRight: browseMove(.right)
        case .tabPrevious, .jumpToStart: stepCategory(-1)
        case .tabNext, .jumpToEnd: stepCategory(1)
        case .confirm: accept()
        case .cancel: back()
        case .secondaryAction:
            if let item = browser.state?.focusedItem { NSWorkspace.shared.open(item.pageURL) }
        default: break
        }
    }

    private func browseMove(_ direction: GridDirection) {
        if searchFocused { searchFocused = false }
        if browser.update({ $0.move(direction) }) { SoundEffectService.shared.play(.focus) }
    }

    private func stepCategory(_ offset: Int) {
        guard let browse = browser.state else { return }
        tapChip(browse.categoryIndex + offset)
    }

    private func tapChip(_ index: Int) {
        guard let browse = browser.state, browse.categories.indices.contains(index) else { return }
        if index == browse.categoryIndex {
            browser.update { $0.focus = .chips; return true }
            if browse.category.isSearch { searchFocused = true }
            return
        }
        browser.update { $0.categoryIndex = index; return true }
        searchFocused = browser.state?.category.isSearch == true
        SoundEffectService.shared.play(.focus)
    }

    private func tapTile(_ index: Int) {
        if browser.state?.focus == .tile(index) { return accept() }
        browser.update { $0.focus = .tile(index); return true }
        SoundEffectService.shared.play(.focus)
    }

    private func submitSearch() {
        let words = searchText
        browser.update { $0.search(words); return true }
        searchFocused = false
    }

    /// A on an online item: apply it if it is here already, else download it first.
    private func choose(_ item: OnlineBackground) {
        let id = OnlineDownload.wallpaperID(for: item)
        if theme.wallpapers.contains(where: { $0.id == id }) { return use(id) }
        SoundEffectService.shared.play(.click)
        transfer.start(item) { result in
            switch result {
            case .success(let id):
                theme.reloadWallpapers()
                use(id)
            case .failure(let error):
                errorTitle = "Couldn't download the wallpaper"
                importError = error.localizedDescription
            }
        }
    }

    private func use(_ id: String) {
        settings.settings.wallpaperID = id
        SoundEffectService.shared.play(.click)
        browser.close()
        state.tab = ThemeBackgrounds.tab(for: id, wallpapers: theme.wallpapers)
        state.backgroundIndex = ThemeBackgrounds.index(of: id, in: backgrounds)
        router.closeMenu()
    }

    private func back() {
        SoundEffectService.shared.play(.focus)
        if transfer.itemID != nil { return transfer.cancel() }
        if searchFocused { searchFocused = false; return }
        if state.step == .background, browser.state != nil { return browser.close() }
        switch state.step {
        case .theme: router.isThemePickerOpen = false
        case .background: state.step = .theme
        }
    }

    /// A plain macOS open panel: picking a file needs the pointer anyway.
    private func addOwn() {
        let live = state.tab == .live
        let panel = NSOpenPanel()
        panel.message = live
            ? "Choose a video for your live background (MP4, MOV or M4V). NX Library keeps its own copy and plays it muted."
            : "Choose a picture for your background. NX Library keeps its own copy."
        panel.allowedContentTypes = live
            ? WallpaperCatalog.videoExtensions.compactMap { UTType(filenameExtension: $0) }
            : [.image]
        panel.allowsMultipleSelection = false
        errorTitle = live ? "Couldn't add the video" : "Couldn't add the picture"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let id = try theme.importWallpaper(from: url)
            state.backgroundIndex = backgrounds.firstIndex(of: .wallpaper(id)) ?? state.backgroundIndex
            SoundEffectService.shared.play(.click)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func removeFocused() {
        guard state.step == .background, browser.state == nil, case .wallpaper(let id) = focusedBackground,
              ThemeStore.isRemovable(id) else { return }
        do {
            try theme.removeWallpaper(id: id)
            if settings.settings.wallpaperID == id { settings.settings.wallpaperID = nil }
            state.backgroundIndex = min(state.backgroundIndex, backgrounds.count - 1)
            SoundEffectService.shared.play(.click)
        } catch {
            errorTitle = "Couldn't remove it"
            importError = error.localizedDescription
        }
    }
}

/// A tile's focus as on Spotlight: it grows and takes a ring 4 outside it.
private struct TileFocus: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    let focused: Bool
    let radius: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: canvas.u(radius + 3), style: .continuous)
                    .strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(3))
                    .padding(canvas.u(-4))
                    .opacity(focused ? 1 : 0))
            .scaleEffect(focused && !reduceMotion ? scale : 1)
            .animation(reduceMotion ? nil : SeleneTheme.quick, value: focused)
    }
}

/// A wallpaper decoded small for a tile (a video's first frame, an online
/// item's thumbnail), kept for the next time it shows.
struct WallpaperThumb: View {
    let url: URL
    var maxPixelSize = 480
    @State private var image: NSImage?

    private static let cache = NSCache<NSURL, NSImage>()

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: url) {
                if let cached = Self.cache.object(forKey: url as NSURL) {
                    image = cached
                    return
                }
                image = nil
                let decoded: NSImage?
                if url.isFileURL {
                    decoded = WallpaperCatalog.kind(of: url) == .video
                        ? await LivePoster.image(for: url, maxPixelSize: CGFloat(maxPixelSize))
                        : await GameArtLoader.decode(at: url, maxPixelSize: maxPixelSize)
                } else if let file = await OnlineBackgroundService.shared.thumbnailFile(for: url) {
                    decoded = await GameArtLoader.decode(at: file, maxPixelSize: maxPixelSize)
                } else {
                    decoded = nil
                }
                guard let decoded, !Task.isCancelled else { return }
                Self.cache.setObject(decoded, forKey: url as NSURL)
                withAnimation(.easeOut(duration: 0.25)) { image = decoded }
            }
    }
}
