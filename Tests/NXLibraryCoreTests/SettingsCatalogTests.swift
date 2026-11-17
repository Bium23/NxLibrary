import XCTest
@testable import NXLibraryCore

final class SettingsCatalogTests: XCTestCase {
    private static let english = AppLocale(language: .english, region: nil, preferredLanguages: ["en"])

    func testDefaultSettingsHaveNoChanges() {
        XCTAssertEqual(SettingsCatalog.changed(in: AppSettings()).map(\.id), [])
    }

    func testChangedListsFlippedRows() {
        var settings = AppSettings()
        settings.interfaceSounds = false
        XCTAssertTrue(SettingsCatalog.changed(in: settings).map(\.id).contains("interfaceSounds"))
    }

    func testRumbleChangesBelongToNewGameDefaults() {
        var settings = AppSettings()
        settings.gameDefaults.rumble.toggle()
        settings.gameDefaults.rumbleGain += 1
        let changed = SettingsCatalog.changed(in: settings)
        XCTAssertEqual(Set(changed.map(\.id)), ["gameDefaults.rumble", "gameDefaults.rumbleGain"])
        XCTAssertTrue(changed.allSatisfy { $0.group == .games })
        XCTAssertTrue(changed.allSatisfy { $0.about.contains("new ported games") })
    }

    /// Every row identity as it was before the regrouping: moving rows never renames them.
    private static let rowIDs: Set<String> = [
        "appLanguage", "appRegion", "startOn", "restoreLastGame", "startInFullscreen", "checkEngineAtLaunch",
        "refreshLibraryAtLaunch", "checkAppUpdatesAtLaunch", "introAnimation", "showButtonHints", "buttonNames",
        "viewButtonSwitches", "spotlightCards", "startingTab", "spotlightOrder", "interfaceSounds", "soundVolume",
        "quietLaunch", "importSeleneSounds", "colorThemeID", "wallpaperID", "settingsWallpaperID", "backgroundSizing",
        "wallpaperBrightness", "animatedBackground", "keepWallpaperOnGames", "backgroundShade", "readableText",
        "showClock", "reduceMotion", "iconAppearance", "boxCovers", "igdb", "steamGridDB", "launchStyle",
        "launchMotion", "launchShade", "surprisePool", "cloudSaves", "cloudSavesPickedFolder", "showsSessionCard",
        "hiddenGames", "gameDefaults.fullscreen", "gameDefaults.enable60FPS", "gameDefaults.isDockedMode",
        "gameDefaults.enableMetalFXUpscale", "gameDefaults.enableMetalHUD", "gameDefaults.language",
        "gameDefaults.renderScale", "controllerStatus", "buttonLayout", "controllerDeadzone", "gameDefaults.rumble",
        "gameDefaults.rumbleGain", "gameFolder", "libraryFolder", "libraryRefresh", "notifyPortingEnds",
        "steamSource", "steamRefresh", "steamFolder", "steamInBackground", "storageUsage", "buildCaches", "logs",
        "metadataCache", "artworkCache", "saveBackups", "console", "engineFolder", "engineStatus",
        "toolchainOverride", "upstream", "newestEngine", "compare", "keys", "setup", "diagnostics", "appUpdates",
        "projectDocs"
    ]

    func testRowIDsAreUnchanged() {
        XCTAssertEqual(SettingsCatalog.all.count, Self.rowIDs.count + 1)
        XCTAssertEqual(Set(SettingsCatalog.all.map(\.id)), Self.rowIDs.union(["particleStyle"]))
    }

    func testEveryRowSitsInItsNewSection() {
        let groups = Dictionary(uniqueKeysWithValues: SettingsCatalog.all.map { ($0.id, $0.group) })
        for id in ["launchStyle", "launchMotion", "launchShade", "surprisePool", "showsSessionCard", "hiddenGames"] {
            XCTAssertEqual(groups[id], .libraryGames, id)
        }
        XCTAssertEqual(groups["cloudSaves"], .cloudSaves)
        XCTAssertEqual(groups["cloudSavesPickedFolder"], .cloudSaves)
        XCTAssertEqual(groups["gameDefaults.rumble"], .games)
        XCTAssertEqual(groups["gameDefaults.rumbleGain"], .games)
        XCTAssertEqual(groups["keys"], .keys)
        XCTAssertEqual(groups["buildCaches"], .portingStorage)
        XCTAssertEqual(groups["console"], .console)
        XCTAssertEqual(groups["logs"], .storage)
        XCTAssertEqual(groups["controllerDeadzone"], .controllers)
    }

    func testSidebarGroupsInOrder() {
        let groups = SettingsSidebarGroup.all
        XCTAssertEqual(groups.map(\.heading), [nil, "Settings group: General", "Settings group: Library",
                                               "Settings group: Porting", "Settings group: System"])
        XCTAssertEqual(groups.map(\.sections), [
            [.search, .changed],
            [.startUp, .navigation, .spotlight, .soundMusic, .look, .controllers, .apiServices],
            [.sources, .libraryGames, .storage],
            [.engine, .keys, .library, .games, .cloudSaves, .portingStorage],
            [.about, .console],
        ])
        XCTAssertEqual(groups.map(\.isPlatform), [false, false, false, true, false])
        XCTAssertEqual(SettingsSection.allCases, groups.flatMap(\.sections), "allCases follows the sidebar")
    }

    func testPortingIsThePlatformGroup() {
        XCTAssertEqual(SettingsSection.games.place(in: Self.english), "Porting · New games")
        XCTAssertEqual(SettingsSection.engine.place(in: Self.english), "Porting · Setup and engine")
        XCTAssertEqual(SettingsSection.sources.place(in: Self.english), "Sources")
        XCTAssertEqual(SettingsSection.apiServices.title(in: Self.english), "Online services")
    }

    func testGroupResetCoversMovedRows() {
        var settings = AppSettings()
        settings.launchMotion.toggle()
        settings.showsSessionCard.toggle()
        settings.gameDefaults.rumble.toggle()
        settings.gameDefaults.fullscreen.toggle()
        settings.cloudSavesPickedFolder = "/Volumes/Saves"

        let library = SettingsReset.reset(.libraryGames, in: settings)
        XCTAssertEqual(library.launchMotion, AppSettings().launchMotion)
        XCTAssertEqual(library.showsSessionCard, AppSettings().showsSessionCard)
        XCTAssertEqual(library.gameDefaults.rumble, settings.gameDefaults.rumble, "Rumble is a new-game default")
        XCTAssertEqual(library.cloudSavesPickedFolder, "/Volumes/Saves")

        let games = SettingsReset.reset(.games, in: settings)
        XCTAssertEqual(games.gameDefaults, AppSettings().gameDefaults)
        XCTAssertEqual(games.launchMotion, settings.launchMotion)

        XCTAssertFalse(SettingsReset.canReset(.cloudSaves))
        XCTAssertEqual(SettingsReset.reset(.cloudSaves, in: settings).cloudSavesPickedFolder, "/Volumes/Saves")
    }

    func testOldSectionRawValuesStillDecode() {
        for raw in ["search", "changed", "startUp", "navigation", "spotlight", "soundMusic", "look", "apiServices",
                    "controllers", "library", "games", "engine", "sources", "storage", "about"] {
            XCTAssertNotNil(SettingsSection(rawValue: raw), raw)
        }
    }

    func testSwitchOnlyRowsLiveInTheSwitchSections() {
        let groups = Dictionary(uniqueKeysWithValues: SettingsCatalog.all.map { ($0.id, $0.group) })
        XCTAssertEqual(groups["checkEngineAtLaunch"], .engine)
        XCTAssertTrue(SettingsCatalog.all.filter { [.engine, .keys, .library, .games, .cloudSaves, .portingStorage].contains($0.group) }
            .allSatisfy { $0.group.group.isPlatform })
        XCTAssertEqual(groups["setup"], .engine)
        XCTAssertEqual(groups["refreshLibraryAtLaunch"], .library)
        XCTAssertEqual(groups["boxCovers"], .library)
        XCTAssertNil(groups["environment"], "Compatibility in Engine re-checks the environment")
        XCTAssertFalse(SettingsCatalog.all.contains { $0.group == .startUp && !Self.generalStartUp.contains($0.id) })
    }

    func testEnvironmentIsFoundOnTheEnginePage() {
        XCTAssertEqual(SettingsCatalog.search("environment").first { $0.id == "engineStatus" }?.group, .engine)
    }

    private static let generalStartUp: Set<String> = [
        "appLanguage", "appRegion", "startOn", "restoreLastGame", "startInFullscreen",
        "checkAppUpdatesAtLaunch", "introAnimation"
    ]

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
        XCTAssertEqual(SettingsCatalog.search("Session card").first { $0.id == "showsSessionCard" }?.group, .libraryGames)
        var settings = AppSettings()
        settings.showsSessionCard = false
        XCTAssertEqual(SettingsCatalog.changed(in: settings).map(\.id), ["showsSessionCard"])
    }

    func testSearchFindsHiddenGames() {
        let hits = SettingsCatalog.search("hidden")
        XCTAssertEqual(hits.first { $0.id == "hiddenGames" }?.group, .libraryGames)
    }

    func testPersonalAPIConnectionsShareAGeneralSectionWithoutChangingSourceIdentity() {
        let connections = SettingsCatalog.all.filter { ["igdb", "steamGridDB"].contains($0.id) }
        XCTAssertEqual(connections.map(\.group), [.apiServices, .apiServices])
        XCTAssertEqual(connections.map(\.id), ["igdb", "steamGridDB"])
        XCTAssertFalse(SettingsSection.apiServices.group.isPlatform)
        XCTAssertEqual(SettingsSection.sources.place(in: Self.english), "Sources")
        XCTAssertTrue(SettingsCatalog.search("API").contains { $0.group == .apiServices })
    }

    func testEmptySearchReturnsNothing() {
        XCTAssertEqual(SettingsCatalog.search("").count, 0)
        XCTAssertEqual(SettingsCatalog.search("   ").count, 0)
    }

    func testVisibleControlNamesCanBeFoundInTheirOwnGroups() {
        let controls: [(String, SettingsSection)] = [
            ("60 FPS", .games), ("Fullscreen", .games), ("Metal HUD", .games),
            ("Render scale", .games), ("App icon", .look),
            ("Stick navigation deadzone", .controllers), ("Cloud saves folder", .cloudSaves),
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
