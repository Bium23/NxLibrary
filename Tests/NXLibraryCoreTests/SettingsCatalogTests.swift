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

    func testSessionCardIsAGamesRowThatCountsAsChanged() {
        XCTAssertEqual(SettingsCatalog.search("Session card").first { $0.id == "showsSessionCard" }?.group, .games)
        var settings = AppSettings()
        settings.showsSessionCard = false
        XCTAssertEqual(SettingsCatalog.changed(in: settings).map(\.id), ["showsSessionCard"])
    }

    func testSearchFindsHiddenGames() {
        let hits = SettingsCatalog.search("hidden")
        XCTAssertEqual(hits.first { $0.id == "hiddenGames" }?.group, .games)
    }

    func testEmptySearchReturnsNothing() {
        XCTAssertEqual(SettingsCatalog.search("").count, 0)
        XCTAssertEqual(SettingsCatalog.search("   ").count, 0)
    }

    func testVisibleControlNamesCanBeFoundInTheirOwnGroups() {
        let controls: [(String, SettingsSection)] = [
            ("60 FPS", .games), ("Fullscreen", .games), ("Metal HUD", .games),
            ("Render scale", .games), ("App icon", .look),
            ("Stick navigation deadzone", .controllers), ("Cloud saves folder", .games),
            ("Engine repository", .engine), ("Game apps", .library), ("Game files", .library)
        ]
        for (name, group) in controls {
            XCTAssertTrue(SettingsCatalog.search(name).contains { $0.group == group }, name)
        }
    }

    func testIndividualNewGameChoicesAreIdentifiableInChanged() {
        var settings = AppSettings()
        settings.gameDefaults.fullscreen = true
        settings.gameDefaults.enableMetalHUD = true
        XCTAssertEqual(Set(SettingsCatalog.changed(in: settings).map(\.id)),
                       ["gameDefaults.fullscreen", "gameDefaults.enableMetalHUD"])
    }

    func testChangedIncludesExternalPreferencesWithoutUnrelatedRows() {
        let changed = SettingsCatalog.changed(in: AppSettings(), externalChanges: ["controllerDeadzone", "iconAppearance"])
        XCTAssertEqual(Set(changed.map(\.id)), ["controllerDeadzone", "iconAppearance"])
        XCTAssertEqual(Set(changed.map(\.group)), [.controllers, .look])
    }

    func testEveryGroupExceptSearchAndChangedHasRows() {
        let groups = Set(SettingsCatalog.all.map(\.group))
        for section in SettingsSection.allCases {
            if [.search, .changed].contains(section) {
                XCTAssertFalse(groups.contains(section), "\(section) should have no rows")
            } else {
                XCTAssertTrue(groups.contains(section), "\(section) has no rows")
            }
        }
    }
}
