import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

/// The background step: its tabs, the background and source tiles, their previews, credits and labels.
extension ThemePickerView {
    // MARK: - Background step

    var backgroundStep: some View {
        let list = backgrounds
        let focused = focusedBackground
        return ZStack(alignment: .top) {
            if let browse = browser.state {
                header(browse.source.title, Self.about(browse.source))
            } else {
                header(L10n.text("Choose your background"), L10n.text("Behind the menus and the home when no game is selected."))
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
                                backgroundTile(list[index], focused: index == state.backgroundIndex,
                                               inUse: list[index] == inUse)
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
                        .onChange(of: state.backgroundIndex) { _, index in
                            withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                                proxy.scrollTo(index - index % ThemePickerState.backgroundColumns, anchor: .center)
                            }
                        }
                    }
                }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ThemePreview(palette: theme.palette, wallpaperURL: previewURL(focused), games: games, width: 820,
                                 videoURL: previewVideo, shade: settings.settings.backgroundShade,
                                 animated: settings.settings.animatedBackground)
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
        .task(id: videoToPreview(focused)) {
            previewVideo = nil
            guard let url = videoToPreview(focused) else { return }
            // Only once the focus rests: moving through the grid streams nothing.
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            previewVideo = url
        }
    }

    /// The video the preview plays for the focus: an online item's small loop, or a video of yours or a download.
    private func videoToPreview(_ choice: ThemeBackgroundChoice) -> URL? {
        guard !reduceMotion, settings.settings.animatedBackground else { return nil }
        if let browse = browser.state { return browse.focusedItem?.previewURL }
        guard case .wallpaper(let id) = choice, let wallpaper = theme.wallpaper(for: id),
              wallpaper.kind == .video else { return nil }
        return wallpaper.url
    }

    /// Wallpapers | Live, between the shoulder badges, as on the home.
    var tabs: some View {
        HStack(spacing: canvas.u(8)) {
            SelenePromptBadge(button: .lb, height: 26).accessibilityHidden(true)
            ForEach(BackgroundTab.allCases, id: \.self) { tab in
                Text(tab == .wallpapers ? L10n.text("Wallpapers") : L10n.text("Live"))
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
        case .wallhaven: return L10n.text("Safe for work, 2K and up. Every picture belongs to its owner.")
        case .danbooru: return L10n.text("General rating only, 2K and up. Every picture belongs to its artist.")
        case .motionbgs: return L10n.text("Looping live wallpapers in 4K and HD. Every video belongs to its owner.")
        case .steam: return L10n.text("Animated profile backgrounds, made by the games' studios for Steam.")
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
            if let author = item.author { parts.append(L10n.format("art by %@", [String(describing: author)])) }
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

    /// The tile of the background in use, marked even when focus is elsewhere.
    private var inUse: ThemeBackgroundChoice? {
        ThemeBackgrounds.inUse(settings.settings.wallpaperID, tab: state.tab,
                               themeID: theme.palette.id, wallpapers: theme.wallpapers)
    }

    private func backgroundTile(_ choice: ThemeBackgroundChoice, focused: Bool, inUse: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(12), style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            Rectangle().fill(SeleneTheme.baseGradient)
            switch choice {
            case .theme:
                if let url = theme.wallpaper(for: nil)?.url { WallpaperThumb(url: url) }
                tileLabel("Theme's own")
            case .none:
                if state.tab == .live {
                    MoonlightBackdrop(accent: SeleneTheme.glyph, ink: SeleneTheme.ink, moving: false, asImage: true,
                                      surface: SeleneTheme.moonlightSurface)
                }
                tileLabel(state.tab == .live ? L10n.text("Moonlight") : "None")
            case .add:
                SeleneTheme.glassSolid
                VStack(spacing: canvas.u(6)) {
                    MaterialIconView(.add, size: 34).foregroundColor(SeleneTheme.ink)
                    Text(state.tab == .live ? L10n.text("Add your video…") : L10n.text("Add your own…")).seleneFont(15).foregroundColor(SeleneTheme.ink90)
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
            if inUse {
                // The theme's accent: a thin inner border and a check in the corner.
                MaterialIconView(.check, size: 18)
                    .foregroundColor(SeleneTheme.glyph)
                    .padding(canvas.u(3))
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .padding(canvas.u(8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: canvas.u(204), height: canvas.u(115))
        .clipShape(shape)
        .overlay(shape.strokeBorder(inUse ? SeleneTheme.glyph : SeleneTheme.ink15,
                                    lineWidth: inUse ? canvas.u(2.5) : 1))
        .modifier(TileFocus(focused: focused, radius: 12, scale: 1.06))
        .padding(.horizontal, canvas.u(11))
        .padding(.top, canvas.u(13))
        .padding(.bottom, canvas.u(14))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(choice))
        .accessibilityValue(inUse ? L10n.text("In use") : "")
        .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
    }

    private func sourceTile(_ source: BackgroundSourceID) -> some View {
        ZStack {
            SeleneTheme.glassSolid
            VStack(spacing: canvas.u(6)) {
                MaterialIconView(.language, size: 30).foregroundColor(SeleneTheme.ink)
                Text(source.title).seleneFont(18, .semibold).foregroundColor(SeleneTheme.ink)
                Text(L10n.text("Browse online")).seleneFont(13).foregroundColor(SeleneTheme.ink60)
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
        case .theme: return L10n.text("Theme's own")
        case .none: return state.tab == .live ? L10n.text("Moonlight") : L10n.text("None")
        case .add: return state.tab == .live ? L10n.text("Add your video") : L10n.text("Add your own")
        case .wallpaper(let id): return theme.wallpaperTitle(for: id)
        case .online(let source): return L10n.format("Browse %@", [String(describing: source.title)])
        }
    }
}
