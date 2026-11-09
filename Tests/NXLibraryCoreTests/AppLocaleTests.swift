import XCTest
@testable import NXLibraryCore

final class AppLocaleTests: XCTestCase {
    func testSettingsTitlesUseTheirExplicitContextWithoutChangingSectionIdentity() {
        let original = L10n.context
        defer { L10n.setContext(original) }
        L10n.setContext(AppLocale(language: .english, region: "US"))
        let identities = SettingsSection.allCases.map(\.id)
        let italian = AppLocale(language: .italian, region: "IT")
        let french = AppLocale(language: .french, region: "FR")
        XCTAssertEqual(SettingsSection.games.title(in: italian), "Giochi")
        XCTAssertEqual(SettingsSection.games.title(in: french), "Jeux")
        XCTAssertEqual(SettingsSection.games.title, "Games")
        XCTAssertEqual(SettingsSection.allCases.map(\.id), identities)
        XCTAssertEqual(SettingsSection.startUp.id, "startUp")
    }

    func testLanguageBundleReuseKeepsInjectedResourcesIsolated() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NXLocalization-\(UUID()).bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("it.lproj")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let strings = ["Games": "INJECTED_TEST_VALUE"]
        try PropertyListSerialization.data(fromPropertyList: strings, format: .xml, options: 0)
            .write(to: folder.appendingPathComponent("Localizable.strings"))
        let bundle = try XCTUnwrap(Bundle(url: root))
        let italian = AppLocale(language: .italian, region: "IT")
        XCTAssertEqual(L10n.text("Games", context: italian), "Giochi")
        XCTAssertEqual(L10n.text("Games", context: italian, bundle: bundle), "INJECTED_TEST_VALUE")
        XCTAssertEqual(L10n.text("Games", context: italian), "Giochi")
        XCTAssertEqual(L10n.text("Games", context: AppLocale(language: .english, region: "IT")), "Games")
    }

    func testCommonGenresRefreshInEveryLanguageAndUnknownGenresStayVerbatim() {
        let previous = L10n.context
        defer { L10n.setContext(previous) }
        let expected: [(AppLanguage, String, String)] = [
            (.english, "Action", "Adventure"), (.italian, "Azione", "Avventura"),
            (.french, "Action", "Aventure"), (.german, "Action", "Abenteuer"),
            (.spanish, "Acción", "Aventura"), (.portugueseBrazil, "Ação", "Aventura")
        ]
        for (language, action, adventure) in expected {
            L10n.setContext(AppLocale(language: language, region: "CH"))
            XCTAssertEqual(GameGenre.list(["Action", "Adventure", "Personal label"]), [action, adventure, "Personal label"])
        }
    }

    func testAutomaticUsesFirstSupportedPreferenceAndIndependentRegion() {
        let context = AppLocale(language: .automatic, region: "CH", preferredLanguages: ["nl-NL", "it-CH"])
        XCTAssertEqual(context.language, .italian)
        XCTAssertEqual(context.region, "CH")
        XCTAssertEqual(context.formatLocale.identifier, "it_CH")
        XCTAssertEqual(context.metadataLanguage, "it")
    }

    func testExplicitLanguageAndPortugueseMapping() {
        let german = AppLocale(language: .german, region: "BR", preferredLanguages: ["it"])
        XCTAssertEqual(german.language, .german)
        XCTAssertEqual(german.formatLocale.identifier, "de_BR")
        let portuguese = AppLocale(language: .automatic, region: "PT", preferredLanguages: ["pt-PT"])
        XCTAssertEqual(portuguese.language, .portugueseBrazil)
        XCTAssertEqual(portuguese.metadataLanguage, "pt")
        XCTAssertEqual(AppLocale(language: .automatic, region: "US", preferredLanguages: ["ja", "nl"]).language, .english)
    }

    func testSettingsMigrationAndInvalidPreferencesDoNotChangeGameLanguage() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.appLanguage, .automatic)
        XCTAssertNil(old.appRegion)
        var settings = old
        settings.appLanguage = .french
        settings.appRegion = "CA"
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.appLanguage, .french)
        XCTAssertEqual(restored.appRegion, "CA")
        XCTAssertEqual(restored.gameDefaults, old.gameDefaults)
        let invalid = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"appLanguage":"future","appRegion":"INVALID"}"#.utf8))
        XCTAssertEqual(invalid.appLanguage, .automatic)
        XCTAssertNil(invalid.appRegion)
    }

    func testSelectedLocaleFormatsGameSizeAndReleaseDate() {
        let original = L10n.context
        defer { L10n.setContext(original) }
        let game = PortedGame(name: "Game", url: URL(fileURLWithPath: "/tmp/Game.app"), platform: .macApp,
                              sizeBytes: 1_500_000_000, modificationDate: Date())
        for (region, decimal) in [("US", "1.5"), ("DE", "1,5")] {
            L10n.setContext(AppLocale(language: .english, region: region))
            let result = GameDetailPresentation(game: game, metadata: nil, totalPlaytime: 0, lastPlayed: nil)
            XCTAssertTrue(result.size.contains(decimal), result.size)
        }
    }

    func testSaveSafetyCopyUsesTheSelectedLanguage() {
        let original = L10n.context
        defer { L10n.setContext(original) }
        L10n.setContext(AppLocale(language: .italian, region: "US"))
        XCTAssertEqual(SavePresentation.slotName(.account), "Salvataggio utente")
        XCTAssertTrue(SavePresentation.closedNotice.contains("Finder"))
        XCTAssertFalse(SavePresentation.closedNotice.hasPrefix("Keep the game"))
    }

    func testCopyRefreshesAfterTheFirstLanguageWasAlreadyUsed() {
        let original = L10n.context
        defer { L10n.setContext(original) }
        L10n.setContext(AppLocale(language: .english, region: "US"))
        let english = NewestEngineCopy.note
        let englishCheats = CheatCopy.about
        L10n.setContext(AppLocale(language: .italian, region: "CH"))
        XCTAssertNotEqual(NewestEngineCopy.note, english)
        XCTAssertNotEqual(CheatCopy.about, englishCheats)
        XCTAssertTrue(SettingsCatalog.search("lingua").contains { $0.id == "appLanguage" })
    }

    func testRegionSearchUsesLocalizedNamesAndStableCountryCodes() {
        let context = AppLocale(language: .spanish, region: "US")
        let choices = AppRegionOption.matching("Suiza", context: context)
        XCTAssertEqual(choices.map(\.id), ["CH"])
        XCTAssertEqual(AppRegionOption.matching("CH", context: context).first { $0.id == "CH" }?.id, "CH")
        XCTAssertTrue(AppRegionOption.matching("zzzznotacountry", context: context).isEmpty)
    }

    func testTechnicalClassificationAndUserTitlesStayIndependentOfUILanguage() {
        let original = L10n.context
        defer { L10n.setContext(original) }
        for language in AppLanguage.allCases where language != .automatic && language != .english {
            L10n.setContext(AppLocale(language: language, region: "CH"))
            let warning = BuildWarningCopy.text(stage: "Pipeline archive", summary: "RAW_INTERNAL_SENTINEL")
            XCTAssertFalse(warning.contains("RAW_INTERNAL_SENTINEL"), language.rawValue)
            let missingTicket = PortingFailureReason(kind: .keys, detail: "missing-common-ticket")
            XCTAssertEqual(missingTicket.action, .none)
            let game = PortedGame(name: "Play", url: URL(fileURLWithPath: "/tmp/Play.app"), platform: .macApp,
                                  sizeBytes: 0, modificationDate: Date())
            XCTAssertEqual(LibraryPresentation(game: game, metadata: nil, totalPlaytime: 0, lastPlayed: nil).title, "Play")
        }
    }

    func testQuantitiesUseCatalogPluralForms() {
        let context = AppLocale(language: .english, region: "US")
        XCTAssertEqual(L10n.count("%lld games found.", 1, context: context), "1 game found.")
        XCTAssertEqual(L10n.count("%lld games found.", 0, context: context), "0 games found.")
        XCTAssertEqual(L10n.count("Detected %lld games in %@.", 2, arguments: ["My games"], context: context), "Detected 2 games in My games.")
    }

    func testTranslationsAndFallbackPreserveUserData() {
        let expected: [(AppLanguage, String)] = [(.italian, "Gioca"), (.french, "Jouer"), (.german, "Spielen"), (.spanish, "Jugar"), (.portugueseBrazil, "Jogar")]
        for (language, value) in expected {
            let context = AppLocale(language: language, region: "CH")
            XCTAssertEqual(L10n.text("Play", context: context), value)
            XCTAssertEqual(L10n.text("Unknown future message", context: context), "Unknown future message")
            let rendered = L10n.format("Delete cache for %@?", ["Settings / Luigi’s Mansion"], context: context)
            XCTAssertTrue(rendered.contains("Settings / Luigi’s Mansion"))
            XCTAssertFalse(rendered.contains("%@"))
        }
    }
}
