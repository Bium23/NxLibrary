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
}
