import XCTest
@testable import NXLibraryCore

final class GameExtraOptionsTests: XCTestCase {
    func testFrameRateWritesAndReadsBack() {
        var config = GameRuntimeConfig()
        config.fpsTarget = 120
        XCTAssertTrue(config.enable60FPS)
        XCTAssertEqual(config.toEnvironmentDict()["DM_FPS_TARGET"], "120")
        XCTAssertEqual(GameRuntimeConfig.parseEnvContent("DM_FPS_TARGET=120\n").fpsTarget, 120)
        config.fpsTarget = 30
        XCTAssertEqual(config.toEnvironmentDict()["DM_FPS_TARGET"], "30")
        config.enable60FPS = true   // the old 60 FPS switch still gives 60 after 30
        XCTAssertEqual(config.fpsTarget, 60)
    }

    func testLayoutAndFillAreWrittenOnlyWhenChosen() {
        var config = GameRuntimeConfig()
        XCTAssertNil(config.toEnvironmentDict()["DM_PAD_LAYOUT"])
        XCTAssertNil(config.toEnvironmentDict()["DM_PRESENT_FILL"])
        // A line the library does not own stays in env.txt
        XCTAssertTrue(config.mergedEnvContent(existing: "DM_PAD_LAYOUT=xbox\n").contains("DM_PAD_LAYOUT=xbox"))
        config.buttonLayout = "xbox"; config.screenFill = "stretch"
        let env = config.envFileContent()
        XCTAssertTrue(env.contains("DM_PAD_LAYOUT=xbox")); XCTAssertTrue(env.contains("DM_PRESENT_FILL=stretch"))
        let back = GameRuntimeConfig.parseEnvContent(env)
        XCTAssertEqual(back.buttonLayout, "xbox"); XCTAssertEqual(back.screenFill, "stretch")
    }

    func testOldSavedConfigDecodes() throws {
        let old = #"{"enable60FPS":true,"enableMetalHUD":false,"isDockedMode":true,"renderScale":1,"enableMetalFXUpscale":false,"language":"auto","rumble":true,"rumbleGain":1,"fullscreen":false}"#
        let config = try JSONDecoder().decode(GameRuntimeConfig.self, from: Data(old.utf8))
        XCTAssertEqual(config.fpsTarget, 60); XCTAssertNil(config.buttonLayout); XCTAssertNil(config.screenFill)
    }

    func testRowsFollowWhatTheAppOffers() {
        let plain = GameOptionsPresentation(supportsRenderScale: true, isPlayable: true, sourcesDetached: false)
        let rows = plain.focusableRows(level: .main, origin: .collection)
        XCTAssertTrue(rows.contains(.fps60)); XCTAssertFalse(rows.contains(.frameRate))
        XCTAssertFalse(rows.contains(.buttonLayout)); XCTAssertFalse(rows.contains(.screenFill))
        let fc26 = GameOptionsPresentation(supportsRenderScale: true, isPlayable: true, sourcesDetached: false,
                                           supportsFrameRate: true, supportsButtonLayout: true, supportsScreenFill: true)
        let more = fc26.focusableRows(level: .main, origin: .collection)
        XCTAssertTrue(more.contains(.frameRate)); XCTAssertFalse(more.contains(.fps60))
        XCTAssertTrue(more.contains(.buttonLayout)); XCTAssertTrue(more.contains(.screenFill))
        XCTAssertTrue(GameOptionsRow.frameRate.isChoice)
    }

    func testFrameRateSteps() {
        XCTAssertEqual(GameOptionsValues.steppedFrameRate(60, by: 1), 120)
        XCTAssertEqual(GameOptionsValues.steppedFrameRate(120, by: 1), 30)
        XCTAssertEqual(GameOptionsValues.steppedFrameRate(30, by: -1), 120)
        XCTAssertEqual(GameOptionsValues.steppedValue(nil, in: GameOptionsValues.buttonLayouts, by: 1), "position")
    }
}

final class BuildSpeedTests: XCTestCase {
    func testShaderJobsKeepEveryCoreBusy() {
        XCTAssertEqual(BuildCommandBuilder.shaderJobs(cores: 8), 10)
        XCTAssertEqual(BuildCommandBuilder.shaderJobs(cores: 1), 4)
    }
}
