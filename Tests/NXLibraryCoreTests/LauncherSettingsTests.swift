import XCTest
@testable import NXLibraryCore

final class LauncherSettingsTests: XCTestCase {
    private func makeApp(_ body: (URL) throws -> Void) throws -> URL {
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("LauncherSettings-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/Resources/dm"),
            withIntermediateDirectories: true
        )
        try body(app)
        addTeardownBlock { try? FileManager.default.removeItem(at: app) }
        return app
    }

    func testReadsTheBotWShapedSettingsList() throws {
        let json = """
        {"game":"01007EF00011E000","settings":[
          {"env":"DM_FPS_TARGET","kind":"choice","section":"Game","label":"Frame rate",
           "note":"Cap","default":"60","options":[["30","30 fps"],["60","60 fps"]]},
          {"env":"DM_RENDER_SCALE","kind":"range","section":"Game","label":"Render scale",
           "default":"1.0","min":0.5,"max":1.0,"step":0.05},
          {"env":"DM_FPS_HOLD","kind":"toggle","section":"Performance","label":"Hold frames when late",
           "default":"on","on":"on","off":"off"}
        ]}
        """
        let app = try makeApp { app in
            try Data(json.utf8).write(to: app.appendingPathComponent("Contents/Resources/dm/launcher.json"))
        }
        let file = LauncherSettingsReader.load(for: app)
        XCTAssertEqual(file?.game, "01007EF00011E000")
        XCTAssertEqual(file?.settings.count, 3)
        XCTAssertEqual(file?.settings[0].options?.map(\.value), ["30", "60"])
        XCTAssertEqual(file?.settings[1].min, 0.5)
        XCTAssertEqual(file?.settings[1].max, 1.0)
        XCTAssertEqual(file?.settings[2].on, "on")
        XCTAssertTrue(LauncherSettingsReader.supports("DM_RENDER_SCALE", for: app))
        XCTAssertTrue(LauncherSettingsReader.supports("DM_FPS_HOLD", for: app))
    }

    func testFallsBackToTheRenderScaleStubForOlderBuilds() throws {
        let app = try makeApp { app in
            try "# TEXT_END\t0x1234\n# RENDER_SCALE\t1\n"
                .write(to: app.appendingPathComponent("Contents/Resources/dm/main.fixups.tsv"),
                       atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(LauncherSettingsReader.supports("DM_RENDER_SCALE", for: app))
        XCTAssertTrue(LauncherSettingsReader.supports("DM_FPS_TARGET", for: app))
    }

    func testHidesRenderScaleWhenTheBuildHasNoStub() throws {
        let app = try makeApp { app in
            try "# TEXT_END\t0x1234\n"
                .write(to: app.appendingPathComponent("Contents/Resources/dm/main.fixups.tsv"),
                       atomically: true, encoding: .utf8)
        }
        XCTAssertFalse(LauncherSettingsReader.supports("DM_RENDER_SCALE", for: app))
        XCTAssertTrue(LauncherSettingsReader.supports("DM_FPS_TARGET", for: app))
    }

    func testAnAppWithoutMetadataHasNoFeatureListButKeepsLegacyDefaults() throws {
        let app = try makeApp { _ in }
        XCTAssertNil(LauncherSettingsReader.load(for: app))
        XCTAssertFalse(LauncherSettingsReader.supports("DM_RENDER_SCALE", for: app))
        XCTAssertTrue(LauncherSettingsReader.supports("DM_FPS_TARGET", for: app))
    }

    private func setting(_ json: String) throws -> LauncherSetting {
        try JSONDecoder().decode(LauncherSetting.self, from: Data(json.utf8))
    }

    func testAcceptsOnlyWhatTheBuildOffers() throws {
        let choice = try setting(#"{"env":"DM_FPS_TARGET","kind":"choice","section":"Game","label":"Frame rate","default":"60","options":[["30","30 fps"],["60","60 fps"]],"level":"basic"}"#)
        XCTAssertEqual(choice.level, "basic")
        XCTAssertTrue(choice.accepts("30"))
        XCTAssertFalse(choice.accepts("120"))

        let toggle = try setting(#"{"env":"DM_RUMBLE","kind":"toggle","section":"Controls","label":"Game rumble","default":"1","on":"1","off":"0"}"#)
        XCTAssertTrue(toggle.accepts("0"))
        XCTAssertFalse(toggle.accepts("true"))

        let range = try setting(#"{"env":"DM_RUMBLE_GAIN","kind":"range","section":"Controls","label":"Rumble strength","default":"1.0","needs":"DM_RUMBLE=1","min":0.0,"max":3.0,"step":0.1}"#)
        XCTAssertTrue(range.accepts("0.45"))
        XCTAssertTrue(range.accepts("3"))
        for bad in [" 1", "0x1", "nan", "3.5", "", "1 ", "inf"] {
            XCTAssertFalse(range.accepts(bad), bad)
        }
    }

    func testRangeDefaultsCompareAsNumbers() throws {
        let range = try setting(#"{"env":"DM_RENDER_SCALE","kind":"range","section":"Game","label":"Render scale","default":"1.0","min":0.5,"max":1.0,"step":0.05}"#)
        XCTAssertTrue(range.isDefault("1"))
        XCTAssertTrue(range.isDefault("1.00"))
        XCTAssertFalse(range.isDefault("0.75"))
        XCTAssertEqual(LauncherSetting.rangeString(1.0), "1")
        XCTAssertEqual(LauncherSetting.rangeString(0.45), "0.45")
        XCTAssertEqual(LauncherSetting.rangeString(0.1 + 0.2), "0.3")
        let choice = try setting(#"{"env":"DM_OPMODE","kind":"choice","section":"Game","label":"Console mode","default":"1","options":[["1","Docked"],["0","Handheld"]]}"#)
        XCTAssertTrue(choice.isDefault("1"))
        XCTAssertFalse(choice.isDefault("1.0"), "only ranges compare as numbers")
    }

    func testNeedsHoldsOnlyForItsValue() throws {
        let range = try setting(#"{"env":"DM_RUMBLE_GAIN","kind":"range","section":"Controls","label":"Rumble strength","default":"1.0","needs":"DM_RUMBLE=1","min":0.0,"max":3.0,"step":0.1}"#)
        XCTAssertEqual(range.needs, "DM_RUMBLE=1")
        XCTAssertTrue(range.needsSatisfied(["DM_RUMBLE": "1"]))
        XCTAssertFalse(range.needsSatisfied(["DM_RUMBLE": "0"]))
        XCTAssertFalse(range.needsSatisfied([:]))
        let free = try setting(#"{"env":"DM_RUMBLE","kind":"toggle","section":"Controls","label":"Game rumble","default":"1","on":"1","off":"0"}"#)
        XCTAssertTrue(free.needsSatisfied([:]))
    }
}
