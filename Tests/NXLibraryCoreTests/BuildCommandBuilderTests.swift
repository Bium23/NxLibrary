import XCTest
@testable import NXLibraryCore

final class BuildCommandBuilderTests: XCTestCase {
    func testMacOnlyJSONCommand() {
        let repo = URL(fileURLWithPath: "/tmp/repo")
        let python = repo.appendingPathComponent(".venv/bin/python")
        let cmd = BuildCommandBuilder.make(
            repo: repo, python: python,
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
        XCTAssertTrue(cmd.environment["DEVELOPER_DIR"]?.contains("Xcode-beta") == true)
    }
}
