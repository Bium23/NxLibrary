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

    func testBackgroundShadeScrimsIncrease() {
        XCTAssertLessThan(BackgroundShade.light.heroScrimOpacity,
                          BackgroundShade.balanced.heroScrimOpacity)
        XCTAssertLessThan(BackgroundShade.balanced.heroScrimOpacity,
                          BackgroundShade.deep.heroScrimOpacity)
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
