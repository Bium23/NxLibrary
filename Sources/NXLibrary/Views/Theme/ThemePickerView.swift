import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

/// The menu's Theme screen (Selene's ProfileSteps from Theme): first the theme's
/// colors, then the background, each beside a preview of the home. A on a theme
/// applies it and goes on; A on a background applies it and closes the menu. B
/// steps back (from the colors: to the menu). The background step adds your own
/// pictures (copied into NX Library) and removes them again with Y (Delete).
struct ThemePickerView: View {
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: AppSettingsStore
    /// The library, for the preview's tiles.
    let games: [PortedGame]

    @ObservedObject private var theme = ThemeStore.shared
    @State private var state = ThemePickerState(themeIndex: 0, backgroundIndex: 0)
    @State private var opened = false
    @State private var importError: String?

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    private var palettes: [SelenePalette] { theme.palettes.isEmpty ? [theme.palette] : theme.palettes }
    private var backgrounds: [ThemeBackgroundChoice] {
        ThemeBackgrounds.list(themeID: theme.palette.id, wallpapers: theme.wallpapers)
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

            SeleneHintsBar(left: [HintItem(.b, "Back", action: back)], right: rightHints,
                           bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear(perform: open)
        .onReceive(NotificationCenter.default.publisher(for: .nxThemePickerGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handle(action)
        }
        .alert("Couldn't add the picture", isPresented: Binding(get: { importError != nil },
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
            var hints: [HintItem] = []
            if case .wallpaper(let id) = focusedBackground, id.hasPrefix(WallpaperCatalog.custom + "/") {
                hints.append(HintItem(.y, "Remove", action: removeFocused))
            }
            hints.append(HintItem(.a, focusedBackground == .add ? "Add" : "Done", action: accept))
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
            header("Choose your background", "Behind the menus and the home when no game is selected.")
            HStack(alignment: .top, spacing: canvas.u(50)) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(ThemeBackgrounds.group(focused))
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
                        .frame(width: canvas.u(3 * 226), height: canvas.u(560))
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                                     .init(color: .black, location: 1 - 150 / 560),
                                                     .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                        .onChange(of: state.backgroundIndex) { index in
                            withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                                proxy.scrollTo(index - index % ThemePickerState.backgroundColumns, anchor: .center)
                            }
                        }
                    }
                }
                ThemePreview(palette: theme.palette, wallpaperURL: wallpaperURL(focused), games: games, width: 820)
            }
            .padding(.top, canvas.u(290))
        }
    }

    private func wallpaperURL(_ choice: ThemeBackgroundChoice) -> URL? {
        switch choice {
        case .theme: return theme.wallpaper(for: nil)?.url
        case .none: return nil
        case .add: return theme.wallpaper(for: settings.settings.wallpaperID)?.url
        case .wallpaper(let id): return theme.wallpaper(for: id)?.url
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
                tileLabel("None")
            case .add:
                SeleneTheme.glassSolid
                VStack(spacing: canvas.u(6)) {
                    MaterialIconView(.add, size: 34).foregroundColor(SeleneTheme.ink)
                    Text("Add your own…").seleneFont(15).foregroundColor(SeleneTheme.ink90)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .wallpaper(let id):
                if let url = theme.wallpaper(for: id)?.url { WallpaperThumb(url: url) }
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
        case .none: return "None"
        case .add: return "Add your own"
        case .wallpaper(let id): return theme.wallpaperTitle(for: id)
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
        state = ThemePickerState(themeIndex: themeIndex,
                                 backgroundIndex: ThemeBackgrounds.index(of: settings.settings.wallpaperID, in: backgrounds))
    }

    private func handle(_ action: GamepadAction) {
        switch action {
        case .navigateUp: move(.up)
        case .navigateDown: move(.down)
        case .navigateLeft: move(.left)
        case .navigateRight: move(.right)
        case .confirm: accept()
        case .cancel: back()
        case .contextAction: removeFocused()
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
            state.backgroundIndex = ThemeBackgrounds.index(
                of: settings.settings.wallpaperID,
                in: ThemeBackgrounds.list(themeID: palette.id, wallpapers: theme.wallpapers))
            state.step = .background
            SoundEffectService.shared.play(.click)
        case .background:
            switch focusedBackground {
            case .add:
                addOwn()
                return
            case .theme: settings.settings.wallpaperID = nil
            case .none: settings.settings.wallpaperID = WallpaperCatalog.none
            case .wallpaper(let id): settings.settings.wallpaperID = id
            }
            SoundEffectService.shared.play(.click)
            router.closeMenu()
        }
    }

    private func back() {
        SoundEffectService.shared.play(.focus)
        switch state.step {
        case .theme: router.isThemePickerOpen = false
        case .background: state.step = .theme
        }
    }

    /// A plain macOS open panel: picking a file needs the pointer anyway.
    private func addOwn() {
        let panel = NSOpenPanel()
        panel.message = "Choose a picture for your background. NX Library keeps its own copy."
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
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
        guard state.step == .background, case .wallpaper(let id) = focusedBackground,
              id.hasPrefix(WallpaperCatalog.custom + "/") else { return }
        do {
            try theme.removeWallpaper(id: id)
            if settings.settings.wallpaperID == id { settings.settings.wallpaperID = nil }
            state.backgroundIndex = min(state.backgroundIndex, backgrounds.count - 1)
            SoundEffectService.shared.play(.click)
        } catch {
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

/// A wallpaper decoded small for a tile, kept for the next time it shows.
struct WallpaperThumb: View {
    let url: URL
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
                guard let decoded = await GameArtLoader.decode(at: url, maxPixelSize: 480), !Task.isCancelled else { return }
                Self.cache.setObject(decoded, forKey: url as NSURL)
                withAnimation(.easeOut(duration: 0.25)) { image = decoded }
            }
    }
}
