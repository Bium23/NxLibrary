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

/// The menu's Theme screen (Selene's ProfileSteps from Theme): the theme's
/// colors first, then the background.
public struct ThemePickerState: Equatable {
    public enum Step: Equatable { case theme, background }

    public static let themeColumns = 5
    public static let backgroundColumns = 3

    public var step: Step = .theme
    public var themeIndex: Int
    public var backgroundIndex: Int

    public init(themeIndex: Int, backgroundIndex: Int) {
        self.themeIndex = themeIndex
        self.backgroundIndex = backgroundIndex
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
    /// No wallpaper: the theme's gradient.
    case none
    /// Add your own picture.
    case add
    case wallpaper(String)
}

public enum ThemeBackgrounds {
    /// Theme's own, none, add, the player's own, the theme's other wallpapers, then every other one.
    public static func list(themeID: String, wallpapers: [Wallpaper]) -> [ThemeBackgroundChoice] {
        let own = WallpaperCatalog.resolve(nil, themeID: themeID, in: wallpapers)?.id
        let custom = wallpapers.filter { $0.theme == WallpaperCatalog.custom }
        let theme = wallpapers.filter { $0.theme == themeID && $0.id != own }
        let rest = wallpapers.filter { $0.theme != WallpaperCatalog.custom && $0.theme != themeID }
        return [.theme, .none, .add] + (custom + theme + rest).map { .wallpaper($0.id) }
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
    public static func group(_ choice: ThemeBackgroundChoice) -> String {
        switch choice {
        case .theme: return "THEME"
        case .none: return "NO WALLPAPER"
        case .add: return "YOUR OWN"
        case .wallpaper(let id):
            let theme = id.split(separator: "/").first.map(String.init) ?? ""
            if theme == WallpaperCatalog.custom { return "YOUR OWN" }
            return theme.split(separator: "-").joined(separator: " ").uppercased()
        }
    }
}
