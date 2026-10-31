import XCTest
@testable import NXLibraryCore

final class LaunchServiceTests: XCTestCase {
    final class FakeLauncher: AppLaunching {
        var opened: URL?
        var environment: [String: String] = [:]
        var shouldSucceed = true
        func open(_ url: URL, environment: [String: String],
                  completion: @escaping (Bool, String?) -> Void) {
            opened = url
            self.environment = environment
            completion(shouldSucceed, shouldSucceed ? nil : "sample launch error")
        }
    }

    func testWritesEnvAndLaunches() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXLaunch-\(UUID().uuidString)")
        let game = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/G.app"),
                              platform: .macApp, sizeBytes: 1, modificationDate: Date(),
                              titleId: "0100000000010000")
        var settings = GameRuntimeConfig()
        settings.fpsTarget = 30
        settings.metalHUD = true
        let launcher = FakeLauncher()
        let service = LaunchService(launcher: launcher)
        try service.writeEnvironment(settings: settings, titleId: "0100000000010000", baseDirectory: dir)
        let env = try String(contentsOf: dir.appendingPathComponent("0100000000010000/env.txt"))
        XCTAssertTrue(env.contains("DM_FPS_TARGET=30"))
        XCTAssertTrue(env.contains("DM_METAL_HUD=1"))
        var launched = false
        var launchError: String?
        service.launch(appURL: game.url, environment: ["DM_FPS_TARGET": "30"]) { success, error in
            launched = success
            launchError = error
        }
        XCTAssertTrue(launched)
        XCTAssertNil(launchError)
        XCTAssertEqual(launcher.opened, game.url)
        XCTAssertEqual(launcher.environment["DM_FPS_TARGET"], "30")
    }

    func testLaunchFailureIsReported() throws {
        let launcher = FakeLauncher()
        launcher.shouldSucceed = false
        let service = LaunchService(launcher: launcher)
        var launched = true
        var launchError: String?
        service.launch(appURL: URL(fileURLWithPath: "/tmp/Missing.app")) { success, error in
            launched = success
            launchError = error
        }
        XCTAssertFalse(launched)
        XCTAssertEqual(launchError, "sample launch error")
    }

    /// NX Library's Game options are the game's settings window: a game it starts skips the engine's own
    /// (dm/mac/launcher.c, DM_LAUNCHER=0), which would ask again and, on Quit, leave a process macOS never reports ended.
    func testLaunchSkipsTheEnginesSettingsWindow() {
        let launcher = FakeLauncher()
        LaunchService(launcher: launcher).launch(appURL: URL(fileURLWithPath: "/tmp/G.app"),
                                                 environment: ["DM_FPS_TARGET": "30"]) { _, _ in }
        XCTAssertEqual(launcher.environment["DM_LAUNCHER"], "0")
        XCTAssertEqual(launcher.environment["DM_FPS_TARGET"], "30")
    }
}
