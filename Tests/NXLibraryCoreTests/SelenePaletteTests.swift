import XCTest
@testable import NXLibraryCore

final class SelenePaletteTests: XCTestCase {
    private var paletteURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Selene/palettes.json")
    }

    func testLoadsAll23Palettes() throws {
        let all = try SelenePaletteCatalog.load(from: paletteURL)
        XCTAssertEqual(all.count, 23)
        let ids = Set(all.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["selene", "white", "catppuccin-latte"]))
    }

    func testSelenePaletteValues() throws {
        let all = try SelenePaletteCatalog.load(from: paletteURL)
        let p = SelenePaletteCatalog.resolve("selene", in: all)
        XCTAssertEqual(p.focus, 0xFFFFFF)
        XCTAssertEqual(p.onFocus, 0x111111)
        XCTAssertEqual(p.glass, 0x14181F)
        XCTAssertEqual(p.glyph, 0x9CCBFF)
        XCTAssertEqual(p.success, 0x3DDC84)
        XCTAssertEqual(p.base.kind, .radial)
        XCTAssertEqual(p.base.stops, [.init(color: 0x102A5C, location: 0), .init(color: 0x03081A, location: 1)])
    }

    func testUnknownIdFallsBackToSelene() throws {
        let all = try SelenePaletteCatalog.load(from: paletteURL)
        XCTAssertEqual(SelenePaletteCatalog.resolve("nope", in: all).id, "selene")
    }

    func testMissingFileUsesFallback() {
        XCTAssertThrowsError(try SelenePaletteCatalog.load(from: URL(fileURLWithPath: "/nonexistent/palettes.json")))
        XCTAssertEqual(SelenePaletteCatalog.resolve("selene", in: []), .fallback)
    }

    func testSettingsDecodeWithoutColorTheme() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.colorThemeID, "selene")
    }
}
