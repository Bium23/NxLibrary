import XCTest
@testable import NXLibraryCore

final class CompatibilityCheckerTests: XCTestCase {
    private final class FakeRunner: CommandRunning {
        var outputs: [String: CommandResult] = [:]
        func run(_ executable: URL, _ arguments: [String],
                 environment: [String: String]?,
                 currentDirectory: URL?) throws -> CommandResult {
            let key = ([executable.lastPathComponent] + arguments).joined(separator: " ")
            if key == CompatibilityCheckerTests.pythonVersionKey {
                return outputs[key] ?? CommandResult(status: 0, stdout: "3.14\n", stderr: "")
            }
            return outputs[key] ?? CommandResult(status: 0, stdout: "", stderr: "")
        }
    }

    private var dir: URL!
    private var repo: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXCompat-\(UUID().uuidString)")
        repo = dir.appendingPathComponent("nxnative")
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent("dm/gfx/tools"),
            withIntermediateDirectories: true
        )
        try """
        metal_macosx\tApple metal version 32023.921 (metalfe-32023.921.6)
        """.write(to: repo.appendingPathComponent("dm/gfx/tools/dmsh_chain.lock"),
                  atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func checker(_ runner: FakeRunner) -> CompatibilityChecker {
        CompatibilityChecker(repoURL: repo,
                             toolchain: EngineToolchain.resolve(runtime: nil, repo: repo),
                             developerDir: nil, runner: runner)
    }

    private var cliKey: String {
        "python " + repo.appendingPathComponent("scripts/build_ipa_from_nsp.py").path + " -h"
    }

    private static let pythonVersionKey = "python -c import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')"

    func testMatchingMetalAndCommitPasses() throws {
        let r = FakeRunner()
        r.outputs["git rev-parse HEAD"] = .init(status: 0, stdout: "06b7b3e\n", stderr: "")
        r.outputs["git status --porcelain"] = .init(status: 0, stdout: "", stderr: "")
        r.outputs["xcrun metal --version"] = .init(status: 0,
            stdout: "Apple metal version 32023.921 (metalfe-32023.921.6)\n", stderr: "")
        r.outputs[cliKey] = .init(status: 0,
            stdout: "--platform --progress -o -k --app-name --bundle-id\n", stderr: "")
        let report = try checker(r).check(expectedEngineCommit: "06b7b3e")
        XCTAssertTrue(report.ok)
    }

    func testMetalMismatchBlocks() throws {
        let r = FakeRunner()
        r.outputs["git rev-parse HEAD"] = .init(status: 0, stdout: "06b7b3e\n", stderr: "")
        r.outputs["git status --porcelain"] = .init(status: 0, stdout: "", stderr: "")
        r.outputs["xcrun metal --version"] = .init(status: 0,
            stdout: "Apple metal version 32023.917\n", stderr: "")
        r.outputs[cliKey] = .init(status: 0,
            stdout: "--platform --progress -o -k --app-name --bundle-id\n", stderr: "")
        let report = try checker(r).check(expectedEngineCommit: "06b7b3e")
        XCTAssertFalse(report.ok)
        XCTAssertTrue(report.checks.contains { $0.id == "metal" && $0.status == .block })
    }

    func testOnlyDmshChainHeaderIsAllowedDirty() throws {
        let r = FakeRunner()
        r.outputs["git rev-parse HEAD"] = .init(status: 0, stdout: "06b7b3e\n", stderr: "")
        r.outputs["git status --porcelain"] = .init(status: 0,
            stdout: " M dm/gfx/nvn/dmsh_chain.h\n M dm/gfx/nvn/nvn_mtl.m\n", stderr: "")
        r.outputs["xcrun metal --version"] = .init(status: 0,
            stdout: "Apple metal version 32023.921\n", stderr: "")
        r.outputs[cliKey] = .init(status: 0,
            stdout: "--platform --progress -o -k --app-name --bundle-id\n", stderr: "")
        let report = try checker(r).check(expectedEngineCommit: "06b7b3e")
        XCTAssertFalse(report.ok)
        XCTAssertTrue(report.checks.contains { $0.id == "tree" && $0.status == .block })
    }

    func testOldPythonVenvBlocks() throws {
        let r = FakeRunner()
        r.outputs["git rev-parse HEAD"] = .init(status: 0, stdout: "06b7b3e\n", stderr: "")
        r.outputs["git status --porcelain"] = .init(status: 0, stdout: "", stderr: "")
        r.outputs["xcrun metal --version"] = .init(status: 0,
            stdout: "Apple metal version 32023.921\n", stderr: "")
        r.outputs[Self.pythonVersionKey] = .init(status: 0, stdout: "3.11\n", stderr: "")
        r.outputs[cliKey] = .init(status: 0,
            stdout: "--platform --progress -o -k --app-name --bundle-id\n", stderr: "")
        let report = try checker(r).check(expectedEngineCommit: "06b7b3e")
        XCTAssertFalse(report.ok)
        XCTAssertTrue(report.checks.contains { $0.id == "python" && $0.status == .block })
    }

    private func report(metal: String) throws -> CompatibilityReport {
        let r = FakeRunner()
        r.outputs["git rev-parse HEAD"] = .init(status: 0, stdout: "06b7b3e\n", stderr: "")
        r.outputs["git status --porcelain"] = .init(status: 0, stdout: "", stderr: "")
        r.outputs["xcrun metal --version"] = .init(status: 0, stdout: metal, stderr: "")
        r.outputs[cliKey] = .init(status: 0,
            stdout: "--platform --progress -o -k --app-name --bundle-id\n", stderr: "")
        return try checker(r).check(expectedEngineCommit: "06b7b3e")
    }

    func testMetalStandingComparesWithTheLock() throws {
        let same = try report(metal: "Apple metal version 32023.921 (metalfe-32023.921.6)\n")
        XCTAssertEqual(same.metal, .same)
        XCTAssertTrue(same.ok)
        let newer = try report(metal: "Apple metal version 32023.922 (metalfe-32023.922.4)\nTarget: air64\n")
        XCTAssertEqual(newer.metal, .newer(installed: "32023.922", required: "32023.921"))
        XCTAssertFalse(newer.ok, "a newer compiler still needs the override (AGENTS.md)")
        XCTAssertEqual(newer.checks.first { $0.id == "metal" }?.detail, "installed 32023.922, tested 32023.921")
        let older = try report(metal: "Apple metal version 32023.917\n")
        XCTAssertEqual(older.metal, .older(installed: "32023.917", required: "32023.921"))
        XCTAssertFalse(older.ok)
        XCTAssertEqual(try report(metal: "").metal, .unknown)
    }

    func testMetalVersionNumbersCompareByComponent() {
        XCTAssertEqual(CompatibilityChecker.metalStanding(installed: "Apple metal version 32023.1000",
                                                          required: "Apple metal version 32023.921"),
                       .newer(installed: "32023.1000", required: "32023.921"))
        XCTAssertEqual(CompatibilityChecker.metalStanding(installed: "32100.1", required: "32023.921"),
                       .newer(installed: "32100.1", required: "32023.921"))
        XCTAssertEqual(CompatibilityChecker.metalStanding(installed: "32023.921", required: "32023.921.0"), .same)
        XCTAssertEqual(CompatibilityChecker.metalStanding(installed: "xcrun: error", required: "32023.921"), .unknown)
    }
}
