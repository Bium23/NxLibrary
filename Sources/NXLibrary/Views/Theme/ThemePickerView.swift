import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

/// The menu's Theme screen (Selene's ProfileSteps from Theme): first the theme's
/// colors, then the background, each beside a preview of the home. A on a theme
/// applies it and goes on; A on a background asks where it goes (Everywhere, Settings only, Not now) and then
/// closes the menu. B
/// steps back (from the colors: to the menu). The background step has two tabs,
/// Wallpapers and Live, switched with LB/RB (Q/E); it adds your own pictures or
/// videos (copied into Arcane) and removes them again with Y (Delete). An
/// online source's tile opens its grid: chips of categories, a search, and A
/// downloads the full picture (B cancels) before applying it.
struct ThemePickerView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: AppSettingsStore
    /// The library, for the preview's tiles.
    let games: [PortedGame]

    @ObservedObject var theme = ThemeStore.shared
    @State var state = ThemePickerState(themeIndex: 0, backgroundIndex: 0)
    @State var opened = false
    @State var errorTitle = L10n.text("Couldn't add the picture")
    @StateObject var browser = OnlineBrowser()
    @StateObject var transfer = OnlineTransfer()
    @State var searchText = ""
    /// The wallpaper waiting on "Remove?", and the dialog's focused pill.
    @State var removal: String?
    @State var removalFocus: SeleneConfirmButton = .cancel
    /// A chosen background waiting on "Where should this wallpaper go?" (nil inside: the theme's own), and the
    /// dialog's focused pill (an index in `WallpaperPlacement.allCases`).
    @State var placing: PendingWallpaper?
    @State var placementFocus = WallpaperPlacement.allCases.count - 1
    /// The focused live item's video, once the focus has rested on it.
    @State var previewVideo: URL?
    @FocusState var searchFocused: Bool

    @Environment(\.seleneCanvas) var canvas
    @Environment(\.seleneReduceMotion) var reduceMotion

    var palettes: [SelenePalette] { theme.palettes.isEmpty ? [theme.palette] : theme.palettes }
    var backgrounds: [ThemeBackgroundChoice] {
        ThemeBackgrounds.list(state.tab, themeID: theme.palette.id, wallpapers: theme.wallpapers,
                              current: settings.settings.wallpaperID)
    }
    var focusedBackground: ThemeBackgroundChoice {
        let list = backgrounds
        return list[min(state.backgroundIndex, list.count - 1)]
    }

    var body: some View {
        ZStack(alignment: .top) {
            SeleneBackdrop().still(true)
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

            SeleneHintsBar(left: [HintItem(.b, transfer.itemID != nil ? L10n.text("Cancel") : L10n.text("Back"), action: back)], right: rightHints,
                           bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
                .frame(maxHeight: .infinity, alignment: .bottom)

            if let removal {
                removalDialog(removal)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            }

            if let placing {
                placementDialog(placing)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: removal)
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: placing)
        .onAppear(perform: open)
        .onReceive(NotificationCenter.default.publisher(for: .nxThemePickerGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handle(action)
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
            return [HintItem(.a, L10n.text("Next"), action: accept)]
        case .background:
            if let browse = browser.state {
                guard transfer.itemID == nil else { return [] }
                if let item = browse.focusedItem {
                    let have = theme.wallpapers.contains { $0.id == OnlineDownload.wallpaperID(for: item) }
                    return [HintItem(.x, L10n.text("Open page"), action: { NSWorkspace.shared.open(item.pageURL) }),
                            HintItem(.a, have ? L10n.text("Done") : L10n.text("Download"), action: accept)]
                }
                return browse.category.isSearch ? [HintItem(.a, L10n.text("Search"), action: accept)] : []
            }
            var hints: [HintItem] = []
            if case .wallpaper(let id) = focusedBackground, let credit = theme.credits[id] {
                hints.append(HintItem(.x, L10n.text("Open page"), action: { NSWorkspace.shared.open(credit.pageURL) }))
            }
            if case .wallpaper(let id) = focusedBackground, ThemeStore.isRemovable(id) {
                hints.append(HintItem(.y, L10n.text("Remove"), action: removeFocused))
            }
            let verb: String
            switch focusedBackground {
            case .add: verb = L10n.text("Add")
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

    func header(_ title: String, _ sub: String) -> some View {
        VStack(spacing: canvas.u(10)) {
            Text(title).seleneFont(44).foregroundColor(SeleneTheme.ink)
            Text(sub).seleneFont(21).foregroundColor(SeleneTheme.ink.opacity(0.7))
        }
        .multilineTextAlignment(.center)
        .padding(.top, canvas.u(110))
    }

    // MARK: - Grid

    func grid<Cell: View>(count: Int, columns: Int, @ViewBuilder cell: @escaping (Int) -> Cell) -> some View {
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

}

/// A tile's focus as on Spotlight: it grows and takes a ring 4 outside it.
struct TileFocus: ViewModifier {
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
