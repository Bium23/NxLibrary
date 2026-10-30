import XCTest
@testable import NXLibraryCore

final class BuildCommandBuilderTests: XCTestCase {
    func testMacOnlyJSONCommand() {
        let repo = URL(fileURLWithPath: "/tmp/repo")
        let cmd = BuildCommandBuilder.make(
            repo: repo, toolchain: EngineToolchain.resolve(runtime: nil, repo: repo),
            workspace: URL(fileURLWithPath: "/tmp/work"),
            keys: URL(fileURLWithPath: "/tmp/prod.keys"),
            output: URL(fileURLWithPath: "/tmp/Game.app"),
            developerDir: URL(fileURLWithPath: "/Applications/Xcode-beta.app/Contents/Developer")
        )
        XCTAssertTrue(cmd.arguments.contains("--platform"))
        XCTAssertTrue(cmd.arguments.contains("mac-app"))
        XCTAssertTrue(cmd.arguments.contains("--progress"))
        XCTAssertTrue(cmd.arguments.contains("json"))
        XCTAssertFalse(cmd.arguments.contains("--show-fps"))
        XCTAssertFalse(cmd.arguments.contains("--allow-other-metal"))
        XCTAssertTrue(cmd.environment["DEVELOPER_DIR"]?.contains("Xcode-beta") == true)
    }

    func testUntestedToolchainOverrideReachesTheEngine() {
        let repo = URL(fileURLWithPath: "/tmp/repo")
        let cmd = BuildCommandBuilder.make(
            repo: repo,
            toolchain: EngineToolchain.resolve(runtime: nil, repo: repo),
            workspace: URL(fileURLWithPath: "/tmp/work"),
            keys: URL(fileURLWithPath: "/tmp/prod.keys"),
            output: URL(fileURLWithPath: "/tmp/Game.app"),
            developerDir: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer"),
            allowUntestedToolchain: true
        )
        XCTAssertTrue(cmd.arguments.contains("--allow-other-metal"))
    }

    func testMotionAndRomfsFlags() {
        let repo = URL(fileURLWithPath: "/tmp/repo")
        let cmd = BuildCommandBuilder.make(
            repo: repo,
            toolchain: EngineToolchain.resolve(runtime: nil, repo: repo),
            workspace: URL(fileURLWithPath: "/tmp/work"),
            keys: URL(fileURLWithPath: "/tmp/prod.keys"),
            output: URL(fileURLWithPath: "/tmp/Game.app"),
            developerDir: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer"),
            motion: true,
            romfsMode: "separate"
        )
        XCTAssertTrue(cmd.arguments.contains("--motion"))
        XCTAssertTrue(cmd.arguments.contains("--romfs"))
        XCTAssertTrue(cmd.arguments.contains("separate"))
    }

    func testBuildCommandUsesToolchain() {
        let repo = URL(fileURLWithPath: "/tmp/repo")
        let runtime = BundledRuntime(root: URL(fileURLWithPath: "/App/Contents/Resources/Runtime"))
        let toolchain = EngineToolchain.resolve(runtime: runtime, repo: repo)
        let cmd = BuildCommandBuilder.make(
            repo: repo, toolchain: toolchain,
            workspace: URL(fileURLWithPath: "/tmp/work"),
            keys: URL(fileURLWithPath: "/tmp/prod.keys"),
            output: URL(fileURLWithPath: "/tmp/Game.app"),
            developerDir: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer")
        )
        XCTAssertEqual(cmd.executable, toolchain.python)
        XCTAssertTrue(cmd.environment["PATH"]?.hasPrefix("/App/Contents/Resources/Runtime/bin:") == true)
        XCTAssertEqual(cmd.environment["PYTHONNOUSERSITE"], "1")
        XCTAssertEqual(cmd.environment["PYTHONUNBUFFERED"], "1")
    }
}
