import XCTest
@testable import NXLibraryCore

final class GameRuntimeConfigTests: XCTestCase {
    func testExistingReviewLoadsTheGameAndSavesTheEditedValues() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NXReview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let env = root.appendingPathComponent("Game.app/Contents/Resources/dm/env.txt")
        try FileManager.default.createDirectory(at: env.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "DM_FPS_TARGET=30\nDM_LANG=it\nDM_RENDER_SCALE=0.75\n".write(to: env, atomically: true, encoding: .utf8)
        let game = PortedGame(name: "Game", url: root.appendingPathComponent("Game.app"), platform: .macApp,
                              sizeBytes: 1, modificationDate: Date())
        defer { UserDefaults.standard.removeObject(forKey: GameRuntimeConfig.storageKey(for: game)) }
        let defaults = GameRuntimeConfig(language: "ja")
        var review = GameRuntimeConfig.forReview(existing: game, defaults: defaults)
        XCTAssertEqual(review.language, "it")
        XCTAssertEqual(review.fpsTarget, 30)
        XCTAssertEqual(review.renderScale, 0.75)
        review.language = "fr"
        try review.save(for: game)
        XCTAssertEqual(GameRuntimeConfig.forReview(existing: game, defaults: defaults).language, "fr")
        XCTAssertEqual(defaults.language, "ja", "Review does not edit the new-game defaults")
    }

    func testNewReviewStartsWithCurrentNewGameDefaults() {
        let defaults = GameRuntimeConfig(enable60FPS: false, language: "it", rumble: false, fullscreen: true)
        XCTAssertEqual(GameRuntimeConfig.forReview(existing: nil, defaults: defaults), defaults)
    }

    func testBuildLanguageBelongsToTheGamesConfiguration() throws {
        let game = try JSONDecoder().decode(GameRuntimeConfig.self,
            from: JSONEncoder().encode(GameRuntimeConfig(language: "it")))
        XCTAssertEqual(game.languageForBuild, "it")
        XCTAssertNil(GameRuntimeConfig(language: "auto").languageForBuild)
        XCTAssertNil(GameRuntimeConfig(language: "").languageForBuild)
    }

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

    func testFailedEnvironmentWriteKeepsPreviousPerTitlePreferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NXRuntimeFailure-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let prefs = try XCTUnwrap(UserDefaults(suiteName: "NXRuntimeFailure-\(UUID())"))
        let game = PortedGame(name: "Fixture", url: root.appendingPathComponent("Game.app"),
                              platform: .macApp, sizeBytes: 0, modificationDate: Date(), titleId: "0100000000000001")
        let previous = try JSONEncoder().encode(GameRuntimeConfig(language: "it"))
        prefs.set(previous, forKey: GameRuntimeConfig.storageKey(for: game))
        defer { prefs.removeObject(forKey: GameRuntimeConfig.storageKey(for: game)) }
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: blocked)
        XCTAssertThrowsError(try GameRuntimeConfig(language: "ja").save(for: game, baseDirectory: blocked, preferences: prefs))
        XCTAssertEqual(prefs.data(forKey: GameRuntimeConfig.storageKey(for: game)), previous)
    }
}
