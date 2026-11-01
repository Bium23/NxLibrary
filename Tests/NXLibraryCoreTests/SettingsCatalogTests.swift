import XCTest
@testable import NXLibraryCore

final class SettingsCatalogTests: XCTestCase {
    func testDefaultSettingsHaveNoChanges() {
        XCTAssertEqual(SettingsCatalog.changed(in: AppSettings()).map(\.id), [])
    }

    func testChangedListsFlippedRows() {
        var settings = AppSettings()
        settings.interfaceSounds = false
        XCTAssertTrue(SettingsCatalog.changed(in: settings).map(\.id).contains("interfaceSounds"))
    }

    func testRumbleChangesBelongToControllersRatherThanGameDefaults() {
        var settings = AppSettings()
        settings.gameDefaults.rumble.toggle()
        settings.gameDefaults.rumbleGain += 1
        let changed = SettingsCatalog.changed(in: settings)
        XCTAssertEqual(Set(changed.map(\.id)), ["gameDefaults.rumble", "gameDefaults.rumbleGain"])
        XCTAssertTrue(changed.allSatisfy { $0.group == .controllers })
    }

    func testSearchMatchesAboutText() {
        let titles = SettingsCatalog.search("crops").map(\.title)
        XCTAssertTrue(titles.contains("Wallpaper sizing"))
    }

    func testWallpaperBrightnessIsFoundAndCountsAsChanged() {
        XCTAssertEqual(SettingsCatalog.search("dark").first { $0.id == "wallpaperBrightness" }?.group, .look)
        var settings = AppSettings()
        settings.wallpaperBrightness = .dim
        XCTAssertEqual(SettingsCatalog.changed(in: settings).map(\.id), ["wallpaperBrightness"])
    }

    func testSearchFindsHiddenGames() {
        let hits = SettingsCatalog.search("hidden")
        XCTAssertEqual(hits.first { $0.id == "hiddenGames" }?.group, .games)
    }

    func testEmptySearchReturnsNothing() {
        XCTAssertEqual(SettingsCatalog.search("").count, 0)
        XCTAssertEqual(SettingsCatalog.search("   ").count, 0)
    }

    func testEveryGroupExceptSearchChangedAboutHasRows() {
        let groups = Set(SettingsCatalog.all.map(\.group))
        for section in SettingsSection.allCases {
            if [.search, .changed, .about].contains(section) {
                XCTAssertFalse(groups.contains(section), "\(section) should have no rows")
            } else {
                XCTAssertTrue(groups.contains(section), "\(section) has no rows")
            }
        }
    }
}
