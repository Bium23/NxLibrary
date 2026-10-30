import XCTest
@testable import NXLibraryCore

final class AppSettingsStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("NXSettings-\(UUID().uuidString).json")
    }

    func testDefaults() {
        let store = AppSettingsStore(fileURL: tempURL())
        XCTAssertEqual(store.settings.backgroundShade, .balanced)
        XCTAssertTrue(store.settings.readableText)
        XCTAssertFalse(store.settings.reduceMotion)
        XCTAssertTrue(store.settings.restoreLastGame)
        XCTAssertNil(store.settings.lastSelectedGameID)
        XCTAssertEqual(store.settings.gameDefaults, GameRuntimeConfig())
        XCTAssertNil(store.loadError)
    }

    func testRoundTrip() {
        let url = tempURL()
        let store = AppSettingsStore(fileURL: url)
        store.settings.backgroundShade = .deep
        store.settings.reduceMotion = true
        store.settings.lastSelectedGameID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        store.settings.gameDefaults.enableMetalFXUpscale = true
        store.save()

        let reloaded = AppSettingsStore(fileURL: url)
        XCTAssertEqual(reloaded.settings.backgroundShade, .deep)
        XCTAssertTrue(reloaded.settings.reduceMotion)
        XCTAssertEqual(reloaded.settings.lastSelectedGameID,
                       UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        XCTAssertTrue(reloaded.settings.gameDefaults.enableMetalFXUpscale)
    }

    func testCorruptFileFallsBackToDefaultsAndKeepsError() throws {
        let url = tempURL()
        try Data("{ not json".utf8).write(to: url)
        let store = AppSettingsStore(fileURL: url)
        XCTAssertEqual(store.settings, AppSettings())
        XCTAssertNotNil(store.loadError)
    }

    func testOldJSONWithoutSpotlightFieldsDecodesDefaults() throws {
        let old = Data(#"{"backgroundShade":"deep","colorThemeID":"selene"}"#.utf8)
        let s = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertEqual(s.backgroundShade, .deep)
        XCTAssertEqual(s.spotlightCards, [.surprise, .activity, .addGame])
        XCTAssertEqual(s.spotlightOrder, [])
        XCTAssertEqual(s.startingTab, "All games")
        XCTAssertEqual(s.surprisePool, .installed)
    }

    func testSettingsWithRetiredSteamGridDBKeyStillDecode() throws {
        let old = Data(#"{"backgroundShade":"deep","steamGridDbApiKey":"abc"}"#.utf8)
        let s = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertEqual(s.backgroundShade, .deep)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(s), as: UTF8.self).contains("steamGridDbApiKey"))
    }

    func testOldSettingsFileDecodesWithDefaults() throws {
        // Only keys written before the Selene fidelity pass.
        let old = Data(#"{"backgroundShade":"deep","readableText":false,"startOn":"collection"}"#.utf8)
        let s = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertEqual(s.backgroundShade, .deep)
        XCTAssertFalse(s.readableText)
        XCTAssertEqual(s.startOn, .collection)
        XCTAssertTrue(s.introAnimation)
        XCTAssertEqual(s.buttonNames, .automatic)
        XCTAssertTrue(s.viewButtonSwitches)
        XCTAssertTrue(s.interfaceSounds)
        XCTAssertEqual(s.soundVolume, 0.6)
        XCTAssertTrue(s.quietLaunch)
        XCTAssertNil(s.wallpaperID)
        XCTAssertEqual(s.backgroundSizing, .fill)
        XCTAssertTrue(s.animatedBackground)
        XCTAssertEqual(s.launchStyle, .artAndLogo)
        XCTAssertTrue(s.launchMotion)
        XCTAssertEqual(s.launchShade, .soft)
    }

    func testNewSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.introAnimation = false
        settings.viewButtonSwitches = false
        settings.interfaceSounds = false
        settings.soundVolume = 0.25
        settings.quietLaunch = false
        settings.wallpaperID = "gruvbox/2-flower-basket"
        settings.backgroundSizing = .stretch
        settings.animatedBackground = false
        settings.launchStyle = .logoOnBlack
        settings.launchMotion = false
        settings.launchShade = .dark
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }

    func testBackgroundShadeScrimsIncrease() {
        XCTAssertLessThan(BackgroundShade.light.heroScrimOpacity,
                          BackgroundShade.balanced.heroScrimOpacity)
        XCTAssertLessThan(BackgroundShade.balanced.heroScrimOpacity,
                          BackgroundShade.deep.heroScrimOpacity)
    }

    func testSpotlightScrimMultipliers() {
        XCTAssertEqual(BackgroundShade.light.scrimMultiplier, 0.7)
        XCTAssertEqual(BackgroundShade.balanced.scrimMultiplier, 1)
        XCTAssertEqual(BackgroundShade.deep.scrimMultiplier, 1.6)
    }
}

final class SettingsSectionTests: XCTestCase {
    func testAllSectionsArePresent() {
        XCTAssertEqual(SettingsSection.allCases.map(\.title), [
            "Search", "Changed", "Start-up", "Navigation", "Spotlight", "Sound & music",
            "Look", "Games", "Controllers", "Library", "Storage", "Engine", "About"
        ])
        XCTAssertTrue(SettingsSection.allCases.allSatisfy { !$0.icon.rawValue.isEmpty })
    }

    func testStartScreenDefaultsAndDecode() throws {
        let settings = AppSettings()
        XCTAssertEqual(settings.startOn, .spotlight)
        XCTAssertEqual(settings.lastHome, .spotlight)

        // Files written before the setting existed decode to the defaults.
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.startOn, .spotlight)
        XCTAssertEqual(old.lastHome, .spotlight)

        let json = Data(#"{"startOn":"last","lastHome":"collection"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(decoded.startOn, .last)
        XCTAssertEqual(decoded.lastHome, .collection)
        XCTAssertEqual(StartScreen.allCases, [.spotlight, .collection, .last])
    }
}
