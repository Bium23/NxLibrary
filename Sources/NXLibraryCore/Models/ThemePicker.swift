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
    /// Both tabs open on a row of the online sources and + Add. Wallpapers: then the
    /// downloads, your own, the theme's own (only when it has one: otherwise it would be
    /// the moonlight twice) and none, the theme's other wallpapers, every other one.
    /// Live: then the moonlight, the downloads, your videos, every other video.
    /// The background in use (`current`, the setting) leads the second row.
    public static func list(_ tab: BackgroundTab = .wallpapers, themeID: String, wallpapers: [Wallpaper],
                            current: String? = nil) -> [ThemeBackgroundChoice] {
        let ordered = baseList(tab, themeID: themeID, wallpapers: wallpapers)
        let top = ordered.prefix { if case .online = $0 { return true } else { return $0 == .add } }.count
        let index = self.index(of: current, in: ordered)
        // On Live, a still in use (or the theme's own picture) is not this tab's: nothing moves.
        guard index >= top, index < ordered.count, tabHolds(current, tab, themeID: themeID, wallpapers: wallpapers) else {
            return ordered
        }
        var list = ordered
        list.insert(list.remove(at: index), at: top)
        return list
    }

    private static func tabHolds(_ current: String?, _ tab: BackgroundTab, themeID: String, wallpapers: [Wallpaper]) -> Bool {
        guard tab == .live else { return true }
        switch current {
        case WallpaperCatalog.none?: return true
        case nil: return WallpaperCatalog.resolve(nil, themeID: themeID, in: wallpapers) == nil
        case let id?: return wallpapers.first { $0.id == id }?.kind == .video
        }
    }

    private static func baseList(_ tab: BackgroundTab, themeID: String,
                                 wallpapers: [Wallpaper]) -> [ThemeBackgroundChoice] {
        let kind: BackgroundKind = tab == .live ? .video : .image
        let items = wallpapers.filter { $0.kind == kind }
        let sources = BackgroundSourceID.allCases.filter { $0.kind == kind }.map(ThemeBackgroundChoice.online)
        let downloaded = items.filter { $0.theme == WallpaperCatalog.online || $0.theme == WallpaperCatalog.live }
        let custom = items.filter { $0.theme == WallpaperCatalog.custom }
        let mine = Set((downloaded + custom).map(\.id))
        switch tab {
        case .wallpapers:
            let own = WallpaperCatalog.resolve(nil, themeID: themeID, in: items)?.id
            let theme = items.filter { $0.theme == themeID && $0.id != own }
            let rest = items.filter { !mine.contains($0.id) && $0.theme != themeID }
            return sources + [.add] + (downloaded + custom).map { .wallpaper($0.id) }
                + (own == nil ? [.none] : [.theme, .none]) + (theme + rest).map { .wallpaper($0.id) }
        case .live:
            let rest = items.filter { !mine.contains($0.id) }
            return sources + [.add, .none] + (downloaded + custom + rest).map { .wallpaper($0.id) }
        }
    }

    /// The tab that holds the setting: Live for a video, Wallpapers otherwise.
    public static func tab(for wallpaperID: String?, wallpapers: [Wallpaper]) -> BackgroundTab {
        guard let wallpaperID, let wallpaper = wallpapers.first(where: { $0.id == wallpaperID }) else {
            return .wallpapers
        }
        return wallpaper.kind == .video ? .live : .wallpapers
    }

    /// The tile for the wallpaper setting. Following the theme, or a file no longer
    /// listed, is Theme's own, or none when the theme has no wallpaper of its own.
    public static func index(of wallpaperID: String?, in list: [ThemeBackgroundChoice]) -> Int {
        let theme = list.firstIndex(of: .theme) ?? list.firstIndex(of: .none) ?? 0
        switch wallpaperID {
        case nil: return theme
        case WallpaperCatalog.none?: return list.firstIndex(of: .none) ?? theme
        case let id?: return list.firstIndex(of: .wallpaper(id)) ?? theme
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
