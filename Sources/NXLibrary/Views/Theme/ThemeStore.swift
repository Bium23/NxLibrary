import Foundation
import NXLibraryCore

/// Holds the active Selene palette. Palettes ship in the app bundle at Resources/Selene/palettes.json;
/// when absent (e.g. `swift run`) the built-in Selene palette is used.
public final class ThemeStore: ObservableObject {
    public static let shared = ThemeStore()

    @Published public private(set) var palette: SelenePalette
    public private(set) var palettes: [SelenePalette]

    public init(palettesURL: URL? = Bundle.main.resourceURL?.appendingPathComponent("Selene/palettes.json"),
                activeID: String = "selene") {
        let loaded = palettesURL.flatMap { try? SelenePaletteCatalog.load(from: $0) } ?? []
        palettes = loaded
        palette = SelenePaletteCatalog.resolve(activeID, in: loaded)
        reloadWallpapers()
    }

    /// Bundled wallpapers plus any imported from a Selene folder.
    @Published public private(set) var wallpapers: [Wallpaper] = []

    /// Call on the main thread: `palette` drives every view.
    public func apply(id: String) {
        guard id != palette.id else { return }
        palette = SelenePaletteCatalog.resolve(id, in: palettes)
    }

    public func reloadWallpapers() {
        var roots: [URL] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Selene/Wallpapers") {
            roots.append(bundled)
        }
        roots.append(SeleneImporter.defaultDestination.appendingPathComponent("Wallpapers"))
        wallpapers = WallpaperCatalog.scan(roots: roots)
    }

    /// The wallpaper to draw for the setting under the active palette.
    public func wallpaper(for wallpaperID: String?) -> Wallpaper? {
        WallpaperCatalog.resolve(wallpaperID, themeID: palette.id, in: wallpapers)
    }

    /// Where the player's own wallpapers are copied (beside imported Selene ones).
    static var customWallpaperFolder: URL {
        SeleneImporter.defaultDestination.appendingPathComponent("Wallpapers")
            .appendingPathComponent(WallpaperCatalog.custom, isDirectory: true)
    }

    /// Copies a picture into the player's own wallpapers; returns its id.
    func importWallpaper(from source: URL) throws -> String {
        let folder = Self.customWallpaperFolder
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let existing = Set(((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [])
            .map { ($0 as NSString).deletingPathExtension })
        let name = WallpaperCatalog.customFileName(for: source.lastPathComponent, existing: existing)
        try fileManager.copyItem(at: source, to: folder.appendingPathComponent(name))
        reloadWallpapers()
        return "\(WallpaperCatalog.custom)/\((name as NSString).deletingPathExtension)"
    }

    /// Moves one of the player's own wallpapers (NX Library's copy) to the Trash.
    func removeWallpaper(id: String) throws {
        guard let wallpaper = wallpapers.first(where: { $0.id == id }),
              wallpaper.theme == WallpaperCatalog.custom else { return }
        try FileManager.default.trashItem(at: wallpaper.url, resultingItemURL: nil)
        reloadWallpapers()
    }

    /// nil follows the theme, "none" hides it, then every wallpaper by id.
    var wallpaperChoices: [String?] {
        [nil, WallpaperCatalog.none] + wallpapers.map(\.id)
    }

    /// The setting's name, as Settings → Look and the control center show it.
    func wallpaperTitle(for wallpaperID: String?) -> String {
        switch wallpaperID {
        case nil:
            return wallpaper(for: nil).map { "Theme (\($0.title))" } ?? "Theme (none)"
        case WallpaperCatalog.none?:
            return "None"
        case let id?:
            return wallpapers.first { $0.id == id }?.title ?? "Missing"
        }
    }
}
