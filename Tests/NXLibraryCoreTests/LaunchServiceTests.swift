import XCTest
@testable import NXLibraryCore

final class LaunchServiceTests: XCTestCase {
    final class FakeLauncher: AppLaunching {
        var opened: URL?
        var shouldSucceed = true
        func open(_ url: URL, completion: @escaping (Bool, String?) -> Void) {
            opened = url
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
        service.launch(appURL: game.url) { success, error in
            launched = success
            launchError = error
        }
        XCTAssertTrue(launched)
        XCTAssertNil(launchError)
        XCTAssertEqual(launcher.opened, game.url)
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
}
