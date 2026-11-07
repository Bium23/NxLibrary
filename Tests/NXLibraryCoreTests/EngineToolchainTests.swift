import XCTest
@testable import NXLibraryCore

final class EngineToolchainTests: XCTestCase {
    private var resources: URL!

    override func setUpWithError() throws {
        resources = FileManager.default.temporaryDirectory
            .appendingPathComponent("EngineToolchainTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: resources)
    }

    private func makePython(mode: Int) throws -> URL {
        let python = resources.appendingPathComponent("Runtime/python/bin/python3")
        try FileManager.default.createDirectory(at: python.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: python)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: python.path)
        return python
    }

    func testLocateNeedsExecutablePython() throws {
        let python = try makePython(mode: 0o755)
        let runtime = BundledRuntime.locate(resourceURL: resources)
        XCTAssertEqual(runtime?.python.path, python.path)
        XCTAssertEqual(runtime?.binDirectory.path, resources.appendingPathComponent("Runtime/bin").path)
        XCTAssertEqual(runtime?.versionsURL.path, resources.appendingPathComponent("Runtime/versions.json").path)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: python.path)
        XCTAssertNil(BundledRuntime.locate(resourceURL: resources))
        XCTAssertNil(BundledRuntime.locate(resourceURL: nil))
    }

    func testVersionSummaryReadsVersionsFile() throws {
        _ = try makePython(mode: 0o755)
        let runtime = try XCTUnwrap(BundledRuntime.locate(resourceURL: resources))
        XCTAssertNil(runtime.versionSummary())

        let json = #"{"glslang": "16.6.0", "python": "3.14.6", "capstone": "5.0.9", "lz4": "4.4.5", "fonttools": "4.67.0", "zbic": "1.0.1.post1", "nsz": "5.0.0", "zstd": "1.5.7"}"#
        try Data(json.utf8).write(to: runtime.versionsURL)
        XCTAssertEqual(runtime.versionSummary(),
                       "Python 3.14.6 · capstone 5.0.9 · lz4 4.4.5 · fonttools 4.67.0 · zbic 1.0.1.post1 · nsz 5.0.0 · zstd 1.5.7 · glslang 16.6.0")
    }

    func testResolveFallsBackToVenv() {
        let repo = URL(fileURLWithPath: "/tmp/nx native")
        let toolchain = EngineToolchain.resolve(runtime: nil, repo: repo)
        XCTAssertEqual(toolchain.python.path, "/tmp/nx native/.venv/bin/python")
        XCTAssertFalse(toolchain.isBundled)
        XCTAssertEqual(toolchain.extraPath, [])
    }

    func testBundledEnvironment() {
        let runtime = BundledRuntime(root: URL(fileURLWithPath: "/App/Contents/Resources/Runtime"))
        let toolchain = EngineToolchain.resolve(runtime: runtime, repo: URL(fileURLWithPath: "/r"))
        XCTAssertTrue(toolchain.isBundled)
        XCTAssertEqual(toolchain.python.path, "/App/Contents/Resources/Runtime/python/bin/python3")

        let env = toolchain.environment(base: ["PATH": "/x", "HOME": "/h"],
                                        developerDir: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer"))
        XCTAssertEqual(env["PATH"], "/App/Contents/Resources/Runtime/bin:" + EngineToolchain.standardPath + ":/h/.dotnet:/x")
        XCTAssertEqual(env["PYTHONNOUSERSITE"], "1")
        XCTAssertEqual(env["PYTHONDONTWRITEBYTECODE"], "1")
        XCTAssertEqual(env["DEVELOPER_DIR"], "/Applications/Xcode.app/Contents/Developer")
        XCTAssertEqual(env["HOME"], "/h")
    }

    func testVenvEnvironmentHasNoPythonFlags() {
        let toolchain = EngineToolchain.resolve(runtime: nil, repo: URL(fileURLWithPath: "/r"))
        let env = toolchain.environment(base: ["PATH": "/x", "HOME": "/h"], developerDir: nil)
        XCTAssertEqual(env["PATH"], EngineToolchain.standardPath + ":/h/.dotnet:/x")
        XCTAssertNil(env["PYTHONNOUSERSITE"])
        XCTAssertNil(env["PYTHONDONTWRITEBYTECODE"])
        XCTAssertNil(env["DEVELOPER_DIR"])
    }

    /// Microsoft's dotnet-install script puts .NET in ~/.dotnet, which the engine also searches (TOOL_PATHS): Setup and
    /// the builds find it there, after the system's own .NET.
    func testDotnetInTheHomeFolderIsFound() {
        let toolchain = EngineToolchain.resolve(runtime: nil, repo: URL(fileURLWithPath: "/r"))
        let path = toolchain.environment(base: ["PATH": "/x", "HOME": "/Users/p"], developerDir: nil)["PATH"] ?? ""
        let folders = path.split(separator: ":").map(String.init)
        let system = folders.firstIndex(of: "/usr/local/share/dotnet")
        let home = folders.firstIndex(of: "/Users/p/.dotnet")
        XCTAssertNotNil(home)
        XCTAssertLessThan(system ?? .max, home ?? -1)
        XCTAssertEqual(folders.last, "/x")
    }
}
