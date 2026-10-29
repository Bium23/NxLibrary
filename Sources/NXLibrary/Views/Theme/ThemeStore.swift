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
    }

    public func apply(id: String) {
        palette = SelenePaletteCatalog.resolve(id, in: palettes)
    }
}
