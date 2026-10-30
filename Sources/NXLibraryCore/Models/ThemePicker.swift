import Foundation

public enum GridDirection: Equatable {
    case up, down, left, right
}

/// Moving through a grid laid out `columns` to a row. Down from above a short
/// last row's gap lands on its last tile.
public enum GridNavigation {
    public static func move(_ index: Int, _ direction: GridDirection, count: Int, columns: Int) -> Int? {
        guard count > 0, columns > 0, (0..<count).contains(index) else { return nil }
        switch direction {
        case .left:
            return index % columns > 0 ? index - 1 : nil
        case .right:
            return index % columns < columns - 1 && index + 1 < count ? index + 1 : nil
        case .up:
            return index >= columns ? index - columns : nil
        case .down:
            if index + columns < count { return index + columns }
            let lastRowStart = (count - 1) / columns * columns
            return index < lastRowStart ? count - 1 : nil
        }
    }
}

/// The background step's two tabs: still pictures, and live (moving) backgrounds.
public enum BackgroundTab: Equatable, CaseIterable {
    case wallpapers, live
}

/// The menu's Theme screen (Selene's ProfileSteps from Theme): the theme's
/// colors first, then the background, as a wallpaper or a live background.
public struct ThemePickerState: Equatable {
    public enum Step: Equatable { case theme, background }

    public static let themeColumns = 5
    public static let backgroundColumns = 3

    public var step: Step = .theme
    public var tab: BackgroundTab = .wallpapers
    public var themeIndex: Int
    public var backgroundIndex: Int

    public init(themeIndex: Int, backgroundIndex: Int) {
        self.themeIndex = themeIndex
        self.backgroundIndex = backgroundIndex
    }

    /// The shoulders switch tabs on the background step; the focus starts at the tab's first tile.
    @discardableResult
    public mutating func switchTab(to tab: BackgroundTab) -> Bool {
        guard step == .background, tab != self.tab else { return false }
        self.tab = tab
        backgroundIndex = 0
        return true
    }

    /// Moves the focus on the current step's grid of `count` tiles.
    @discardableResult
    public mutating func move(_ direction: GridDirection, count: Int) -> Bool {
        switch step {
        case .theme:
            guard let next = GridNavigation.move(themeIndex, direction, count: count, columns: Self.themeColumns) else { return false }
            themeIndex = next
        case .background:
            guard let next = GridNavigation.move(backgroundIndex, direction, count: count,
                                                 columns: Self.backgroundColumns) else { return false }
            backgroundIndex = next
        }
        return true
    }
}

/// One tile of the background step.
public enum ThemeBackgroundChoice: Equatable, Hashable {
    /// The theme's own wallpaper (or its drawn backdrop).
    case theme
    /// No wallpaper: the theme's gradient and its moonlight (on Live: the theme's own).
    case none
    /// Add your own picture (on Live: your own video).
    case add
    case wallpaper(String)
    /// Browse a source's grid online.
    case online(BackgroundSourceID)
}

public enum ThemeBackgrounds {
    /// Wallpapers: theme's own, none, add, the player's own, the downloaded ones,
    /// the online sources, the theme's other wallpapers, then every other one. Live: the theme's own (the moonlight),
    /// add, the player's videos, then every other video.
    public static func list(_ tab: BackgroundTab = .wallpapers, themeID: String,
                            wallpapers: [Wallpaper]) -> [ThemeBackgroundChoice] {
        switch tab {
        case .wallpapers:
            let stills = wallpapers.filter { $0.kind == .image }
            let own = WallpaperCatalog.resolve(nil, themeID: themeID, in: stills)?.id
            let custom = stills.filter { $0.theme == WallpaperCatalog.custom }
            let downloaded = stills.filter { $0.theme == WallpaperCatalog.online }
            let theme = stills.filter { $0.theme == themeID && $0.id != own }
            let rest = stills.filter { ![WallpaperCatalog.custom, WallpaperCatalog.online, themeID].contains($0.theme) }
            let sources = BackgroundSourceID.allCases.filter { $0.kind == .image }.map(ThemeBackgroundChoice.online)
            return [.theme, .none, .add] + (custom + downloaded).map { .wallpaper($0.id) } + sources
                + (theme + rest).map { .wallpaper($0.id) }
        case .live:
            let videos = wallpapers.filter { $0.kind == .video }
            let custom = videos.filter { $0.theme == WallpaperCatalog.custom }
            let rest = videos.filter { $0.theme != WallpaperCatalog.custom }
            return [.none, .add] + (custom + rest).map { .wallpaper($0.id) }
        }
    }

    /// The tab that holds the setting: Live for a video, Wallpapers otherwise.
    public static func tab(for wallpaperID: String?, wallpapers: [Wallpaper]) -> BackgroundTab {
        guard let wallpaperID, let wallpaper = wallpapers.first(where: { $0.id == wallpaperID }) else {
            return .wallpapers
        }
        return wallpaper.kind == .video ? .live : .wallpapers
    }

    /// The tile for the wallpaper setting; Theme's own when it is not listed.
    public static func index(of wallpaperID: String?, in list: [ThemeBackgroundChoice]) -> Int {
        switch wallpaperID {
        case nil: return 0
        case WallpaperCatalog.none?: return list.firstIndex(of: .none) ?? 0
        case let id?: return list.firstIndex(of: .wallpaper(id)) ?? 0
        }
    }

    /// The label over the grid for the focused tile.
    public static func group(_ choice: ThemeBackgroundChoice, tab: BackgroundTab = .wallpapers) -> String {
        switch choice {
        case .theme: return "THEME"
        case .none: return tab == .live ? "THEME" : "NO WALLPAPER"
        case .add: return "YOUR OWN"
        case .online(let source): return "ONLINE · \(source.title.uppercased())"
        case .wallpaper(let id):
            let theme = id.split(separator: "/").first.map(String.init) ?? ""
            if theme == WallpaperCatalog.custom { return "YOUR OWN" }
            if theme == WallpaperCatalog.online || theme == WallpaperCatalog.live { return "DOWNLOADED" }
            return theme.split(separator: "-").joined(separator: " ").uppercased()
        }
    }
}
