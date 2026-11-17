import XCTest
@testable import NXLibraryCore

final class SelenePaletteTests: XCTestCase {
    private var paletteURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Selene/palettes.json")
    }

    func testLoadsAll25Palettes() throws {
        let all = try SelenePaletteCatalog.load(from: paletteURL)
        XCTAssertEqual(all.count, 25)
        let ids = Set(all.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["selene", "white", "catppuccin-latte"]))
    }

    /// The picker: Selene, the default, first; then the rest by name.
    func testPickerOrderPutsTheDefaultFirstThenAlphabetical() throws {
        let ordered = SelenePaletteCatalog.pickerOrder(try SelenePaletteCatalog.load(from: paletteURL))
        XCTAssertEqual(ordered.first?.id, SelenePaletteCatalog.defaultID)
        XCTAssertEqual(SelenePaletteCatalog.defaultID, "selene")
        let rest = ordered.dropFirst().map(\.name)
        XCTAssertEqual(rest, rest.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        XCTAssertEqual(Array(rest.prefix(3)), ["Arcane Crystal", "Arcane Flow", "Catppuccin"])
        XCTAssertEqual(ordered.count, 25)
    }

    func testSelenePaletteValues() throws {
        let all = try SelenePaletteCatalog.load(from: paletteURL)
        let p = SelenePaletteCatalog.resolve("selene", in: all)
        XCTAssertEqual(p.name, AppIdentity.name)
        XCTAssertEqual(p.focus, 0xFFFFFF)
        XCTAssertEqual(p.onFocus, 0x111111)
        XCTAssertEqual(p.glass, 0x14181F)
        XCTAssertEqual(p.glyph, 0x9CCBFF)
        XCTAssertEqual(p.success, 0x3DDC84)
        XCTAssertEqual(p.base.kind, .radial)
        XCTAssertEqual(p.base.stops, [.init(color: 0x0C1123, location: 0), .init(color: 0x060812, location: 1)])
    }

    func testBothArcaneSurfacesAreSelectableAndOldPalettesStayClassic() throws {
        let all = try SelenePaletteCatalog.load(from: paletteURL)
        XCTAssertEqual(SelenePaletteCatalog.resolve("selene", in: all).surface, .classic)
        XCTAssertEqual(SelenePaletteCatalog.resolve("arcane-crystal", in: all).surface, .arcane)
        XCTAssertEqual(SelenePaletteCatalog.resolve("arcane-flow", in: all).surface, .flow)
        XCTAssertEqual(SelenePaletteCatalog.resolve("white", in: all).surface, .classic)
        var settings = AppSettings()
        settings.colorThemeID = "arcane-flow"
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).colorThemeID, "arcane-flow")
    }

    func testUnknownIdFallsBackToSelene() throws {
        let all = try SelenePaletteCatalog.load(from: paletteURL)
        XCTAssertEqual(SelenePaletteCatalog.resolve("nope", in: all).id, "selene")
    }

    func testMissingFileUsesFallback() {
        XCTAssertThrowsError(try SelenePaletteCatalog.load(from: URL(fileURLWithPath: "/nonexistent/palettes.json")))
        XCTAssertEqual(SelenePaletteCatalog.resolve("selene", in: []), .fallback)
        XCTAssertEqual(SelenePalette.fallback.surface, .classic)
    }

    func testSettingsDecodeWithoutColorTheme() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.colorThemeID, "selene")
        XCTAssertEqual(SelenePaletteCatalog.resolve(settings.colorThemeID, in: []).surface, .classic)
    }
}
