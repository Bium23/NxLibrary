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
        XCTAssertEqual(SettingsSection.allCases.count, 8)
        XCTAssertEqual(SettingsSection.allCases.map(\.title), [
            "General", "Appearance", "Library", "Game defaults",
            "Controllers", "Engine & keys", "Storage & logs", "About"
        ])
        XCTAssertTrue(SettingsSection.allCases.allSatisfy { !$0.icon.isEmpty })
    }
}
