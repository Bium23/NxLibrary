import XCTest
@testable import NXLibraryCore

final class WallpaperPlacementTests: XCTestCase {
    func testDefaultsKeepTodaysLook() throws {
        let s = AppSettings()
        XCTAssertNil(s.settingsWallpaperID, "Settings follow the app")
        XCTAssertFalse(s.keepWallpaperOnGames)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertNil(old.settingsWallpaperID)
        XCTAssertFalse(old.keepWallpaperOnGames)
    }

    func testSettingsRoundTrip() throws {
        var s = AppSettings()
        s.settingsWallpaperID = "live/rain"
        s.keepWallpaperOnGames = true
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.settingsWallpaperID, "live/rain")
        XCTAssertTrue(back.keepWallpaperOnGames)
    }

    func testSettingsWallpaperResolvesAgainstTheApp() {
        XCTAssertEqual(WallpaperCatalog.settingsWallpaper(settingsID: nil, appID: "online/a"), "online/a")
        XCTAssertNil(WallpaperCatalog.settingsWallpaper(settingsID: nil, appID: nil), "same as the app: its theme")
        XCTAssertNil(WallpaperCatalog.settingsWallpaper(settingsID: WallpaperCatalog.themeOwn, appID: "online/a"))
        XCTAssertEqual(WallpaperCatalog.settingsWallpaper(settingsID: "none", appID: "online/a"), "none")
        XCTAssertEqual(WallpaperCatalog.settingsWallpaper(settingsID: "live/rain", appID: "online/a"), "live/rain")
    }

    func testEverywhereSetsTheAppAndSettingsFollow() {
        var s = AppSettings()
        s.settingsWallpaperID = "live/rain"
        WallpaperPlacement.everywhere.apply("online/a", to: &s)
        XCTAssertEqual(s.wallpaperID, "online/a")
        XCTAssertNil(s.settingsWallpaperID)
        WallpaperPlacement.everywhere.apply(nil, to: &s)
        XCTAssertNil(s.wallpaperID, "the theme's own")
    }

    func testSettingsOnlyLeavesTheApp() {
        var s = AppSettings()
        s.wallpaperID = "online/a"
        WallpaperPlacement.settingsOnly.apply("live/rain", to: &s)
        XCTAssertEqual(s.wallpaperID, "online/a")
        XCTAssertEqual(s.settingsWallpaperID, "live/rain")
        WallpaperPlacement.settingsOnly.apply(nil, to: &s)
        XCTAssertEqual(s.settingsWallpaperID, WallpaperCatalog.themeOwn, "the theme's own, not 'same as the app'")
    }

    func testNotNowChangesNothing() {
        var s = AppSettings()
        s.wallpaperID = "online/a"
        let before = s
        WallpaperPlacement.notNow.apply("live/rain", to: &s)
        XCTAssertEqual(s, before)
    }

    func testDialogCopy() {
        XCTAssertEqual(WallpaperPlacement.dialogTitle, "Where should this wallpaper go?")
        XCTAssertEqual(WallpaperPlacement.allCases.map(\.title), ["Not now", "Settings only", "App & Settings"])
    }
}
