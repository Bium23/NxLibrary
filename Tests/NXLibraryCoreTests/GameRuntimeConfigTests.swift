import XCTest
@testable import NXLibraryCore

final class GameRuntimeConfigTests: XCTestCase {
    func testDefaultLanguageIsAutoAndOmitted() {
        let config = GameRuntimeConfig()
        XCTAssertEqual(config.language, "auto")
        XCTAssertFalse(config.toEnvironmentDict().keys.contains("DM_LANG"))
        XCTAssertFalse(config.envFileContent().contains("DM_LANG="))
    }

    func testMergePreservesUnknownKeysAndUpdatesKnownOnes() {
        let existing = "DM_SHOW_FPS=1\nDM_FPS_TARGET=30\nDM_LANG=fr\n"
        var config = GameRuntimeConfig()
        config.fpsTarget = 60
        config.language = "ja"
        let merged = config.mergedEnvContent(existing: existing)
        XCTAssertTrue(merged.contains("DM_SHOW_FPS=1"))
        XCTAssertTrue(merged.contains("DM_FPS_TARGET=60"))
        XCTAssertTrue(merged.contains("DM_LANG=ja"))
    }

    func testAutoLanguageRemovesExistingOverride() {
        var config = GameRuntimeConfig()
        config.language = "auto"
        let merged = config.mergedEnvContent(existing: "DM_LANG=fr\nDM_SHOW_FPS=1\n")
        XCTAssertFalse(merged.contains("DM_LANG="))
        XCTAssertTrue(merged.contains("DM_SHOW_FPS=1"))
    }

    func testParseExistingEnv() {
        let config = GameRuntimeConfig.parseEnvContent("DM_FPS_TARGET=30\nDM_LANG=ja\nDM_METAL_HUD=1\n")
        XCTAssertFalse(config.enable60FPS)
        XCTAssertEqual(config.language, "ja")
        XCTAssertTrue(config.metalHUD)
    }
}
