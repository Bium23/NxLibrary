import XCTest
@testable import NXLibraryCore

final class EnvironmentTests: XCTestCase {
    private final class RecordingRunner: CommandRunning {
        var calls: [String] = []
        var environments: [[String: String]?] = []
        func run(_ executable: URL, _ arguments: [String],
                 environment: [String: String]?,
                 currentDirectory: URL?) throws -> CommandResult {
            calls.append(([executable.lastPathComponent] + arguments).joined(separator: " "))
            environments.append(environment)
            return .init(status: 0, stdout: "", stderr: "")
        }
    }

    private final class FakeRunner: CommandRunning {
        var sdks = "10.0.401 [/usr/local/share/dotnet/sdk]\n"
        func run(_ executable: URL, _ arguments: [String],
                 environment: [String: String]?,
                 currentDirectory: URL?) throws -> CommandResult {
            if arguments == ["-version"] {
                return .init(status: 0, stdout: "Xcode 27.0\nBuild version 27A5194q\n", stderr: "")
            }
            if arguments == ["metal", "--version"] {
                return .init(status: 0, stdout: "Apple metal version 32023.917\n", stderr: "")
            }
            if arguments == ["dotnet", "--list-sdks"] {
                return .init(status: 0, stdout: sdks, stderr: "")
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

        let env = NXNativeEnvironment(repoURL: repo, toolchain: .resolve(runtime: nil, repo: repo), runner: FakeRunner())
        let status = env.inspect()
        XCTAssertEqual(status.metalVersion, "32023.917")
        XCTAssertEqual(status.xcodeVersion, "Xcode 27.0")
        XCTAssertTrue(status.canBuild, status.issues.joined(separator: "; "))
        try? FileManager.default.removeItem(at: repo)
    }

    private func makeRepo() throws -> URL {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXEnvTools-\(UUID().uuidString)")
        for dir in ["scripts", "dm", ".venv/bin"] {
            try FileManager.default.createDirectory(
                at: repo.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        for file in ["scripts/build_ipa_from_nsp.py", ".venv/bin/python"] {
            try "".write(to: repo.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        return repo
    }

    func testInspectChecksOnlyEngineTools() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let runner = RecordingRunner()
        let status = NXNativeEnvironment(repoURL: repo, toolchain: .resolve(runtime: nil, repo: repo),
                                         runner: runner).inspect()
        XCTAssertTrue(runner.calls.contains("env zstd --version"))
        XCTAssertTrue(runner.calls.contains("env glslangValidator --version"))
        XCTAssertTrue(runner.calls.contains("env dotnet --list-sdks"))
        XCTAssertFalse(runner.calls.contains { $0.contains("xcodegen") || $0.contains("spirv-cross") })
        XCTAssertTrue(runner.calls.contains("env make --version"))
        XCTAssertEqual(status.tools.map(\.id), ["zstd", "glslangValidator", "make"])
        XCTAssertTrue(runner.environments.contains {
            $0?["PATH"]?.hasPrefix(EngineToolchain.standardPath) == true
        })
    }

    func testInspectPutsBundledToolsFirst() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let runner = RecordingRunner()
        let runtime = BundledRuntime(root: URL(fileURLWithPath: "/App/Runtime"))
        _ = NXNativeEnvironment(repoURL: repo, toolchain: .resolve(runtime: runtime, repo: repo),
                                runner: runner).inspect()
        XCTAssertTrue(runner.environments.allSatisfy { $0?["PATH"]?.hasPrefix("/App/Runtime/bin:") == true })
    }

    func testDotnetNeedsSDK10() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let runner = FakeRunner()
        let toolchain = EngineToolchain.resolve(runtime: nil, repo: repo)
        XCTAssertFalse(NXNativeEnvironment(repoURL: repo, toolchain: toolchain, runner: runner)
            .inspect().issues.contains("the .NET 10 SDK is missing"))
        runner.sdks = "9.0.100 [/usr/local/share/dotnet/sdk]\n"
        XCTAssertTrue(NXNativeEnvironment(repoURL: repo, toolchain: toolchain, runner: runner)
            .inspect().issues.contains("the .NET 10 SDK is missing"))
    }
}
