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
}
