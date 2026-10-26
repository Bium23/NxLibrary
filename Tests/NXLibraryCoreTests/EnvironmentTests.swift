import XCTest
@testable import NXLibraryCore

final class EnvironmentTests: XCTestCase {
    private final class FakeRunner: CommandRunning {
        func run(_ executable: URL, _ arguments: [String],
                 environment: [String: String]?,
                 currentDirectory: URL?) throws -> CommandResult {
            if arguments == ["-version"] {
                return .init(status: 0, stdout: "Xcode 27.0\nBuild version 27A5194q\n", stderr: "")
            }
            if arguments == ["metal", "--version"] {
                return .init(status: 0, stdout: "Apple metal version 32023.917\n", stderr: "")
            }
            if arguments == ["dotnet", "--list-runtimes"] {
                return .init(status: 0, stdout: "Microsoft.NETCore.App 10.0.12\n", stderr: "")
            }
            return .init(status: 0, stdout: "", stderr: "")
        }
    }

    func testMetalVersionParser() {
        XCTAssertEqual(
            MetalVersion.parse("Apple metal version 32023.917 (metalfe-32023.917)"),
            "32023.917"
        )
    }

    func testInspectWithFakeRunner() throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXEnv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent("dm"), withIntermediateDirectories: true)
        try "".write(to: repo.appendingPathComponent("scripts/build_ipa_from_nsp.py"),
                     atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".venv/bin"), withIntermediateDirectories: true)
        try "".write(to: repo.appendingPathComponent(".venv/bin/python"),
                     atomically: true, encoding: .utf8)

        let env = NXNativeEnvironment(repoURL: repo, runner: FakeRunner())
        let status = env.inspect()
        XCTAssertEqual(status.metalVersion, "32023.917")
        XCTAssertEqual(status.xcodeVersion, "Xcode 27.0")
        XCTAssertTrue(status.canBuild, status.issues.joined(separator: "; "))
        try? FileManager.default.removeItem(at: repo)
    }
}
