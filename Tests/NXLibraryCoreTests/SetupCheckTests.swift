import XCTest
@testable import NXLibraryCore

final class SetupCheckTests: XCTestCase {
    private let pin = "af616f54652fa7f50a2e223ceed1d08a9bc83848"
    private let folder = URL(fileURLWithPath: "/Users/a b/nxnative")

    private func facts() -> SetupFacts {
        SetupFacts(xcodeStatus: 0, metalVersion: "32023.921", certifiedMetal: "32023.921", allowUntested: false,
                   dotnetSDKs: ["10.0.401 [/usr/local/share/dotnet/sdk]"],
                   engine: .checkout(head: pin, dirty: false), engineFolder: folder, pinnedCommit: pin,
                   runtimeProblem: nil,
                   keys: KeySummary(hasHeaderKey: true, applicationKeyGenerations: [0, 1, 2]), keysError: nil,
                   libraryWritable: true)
    }

    private func item(_ id: SetupItemID, _ change: (inout SetupFacts) -> Void = { _ in }) -> SetupItem {
        var f = facts()
        change(&f)
        return SetupCheck.items(from: f).first { $0.id == id }!
    }

    func testAllReadyInCardOrder() {
        let items = SetupCheck.items(from: facts())
        XCTAssertEqual(items.map(\.id), SetupItemID.allCases)
        XCTAssertTrue(items.allSatisfy { $0.state == .ready }, items.map(\.chip).joined(separator: ", "))
    }

    func testXcode() {
        XCTAssertEqual(item(.xcode) { $0.xcodeStatus = nil }.state, .missing)
        XCTAssertEqual(item(.xcode) { $0.xcodeStatus = nil }.chip, "NOT INSTALLED")
        XCTAssertEqual(item(.xcode) { $0.xcodeStatus = nil }.actionTitle, "Get Xcode")
        XCTAssertEqual(item(.xcode) { $0.xcodeStatus = 69 }.state, .needsYou)
        XCTAssertEqual(item(.xcode) { $0.xcodeStatus = 69 }.chip, "OPEN XCODE ONCE")
        XCTAssertEqual(item(.xcode).chip, "✓ READY")
    }

    func testMetal() {
        let missing = item(.metal) { $0.metalVersion = nil }
        XCTAssertEqual(missing.state, .missing)
        XCTAssertEqual(missing.chip, "NOT INSTALLED")
        XCTAssertEqual(missing.actionTitle, "Install")

        let other = item(.metal) { $0.metalVersion = "32023.917" }
        XCTAssertEqual(other.state, .warning)
        XCTAssertEqual(other.chip, "NOT CERTIFIED")
        XCTAssertNil(other.actionTitle)

        let overridden = item(.metal) { $0.metalVersion = "32023.917"; $0.allowUntested = true }
        XCTAssertEqual(overridden.state, .ready)
        XCTAssertTrue(overridden.detail.contains("untested toolchain override is on"))

        XCTAssertEqual(item(.metal).state, .ready)
    }

    func testDotnet() {
        XCTAssertEqual(item(.dotnet).state, .ready)
        for sdks in [["9.0.1 [/usr/local/share/dotnet/sdk]"], []] {
            let card = item(.dotnet) { $0.dotnetSDKs = sdks }
            XCTAssertEqual(card.state, .missing)
            XCTAssertEqual(card.chip, "NOT INSTALLED")
            XCTAssertEqual(card.actionTitle, "Install")
        }
    }

    func testEngine() {
        let missing = item(.engine) { $0.engine = .missing }
        XCTAssertEqual(missing.state, .missing)
        XCTAssertEqual(missing.chip, "NOT INSTALLED")
        XCTAssertEqual(missing.actionTitle, "Clone")

        XCTAssertEqual(item(.engine).state, .ready)

        let other = item(.engine) { $0.engine = .checkout(head: "ee369f0", dirty: false) }
        XCTAssertEqual(other.state, .warning)
        XCTAssertEqual(other.chip, "WRONG COMMIT")
        XCTAssertEqual(other.actionTitle, "Check out")

        let dirty = item(.engine) { $0.engine = .checkout(head: "ee369f0", dirty: true) }
        XCTAssertEqual(dirty.state, .warning)
        XCTAssertEqual(dirty.chip, "LOCAL CHANGES")
        XCTAssertNil(dirty.actionTitle)
        XCTAssertTrue(dirty.detail.contains(folder.path))

        let notRepo = item(.engine) { $0.engine = .notACheckout }
        XCTAssertEqual(notRepo.state, .warning)
        XCTAssertEqual(notRepo.chip, "NOT A CHECKOUT")
        XCTAssertNil(notRepo.actionTitle)
    }

    func testRuntime() {
        XCTAssertEqual(item(.runtime).chip, "✓ INCLUDED")
        let broken = item(.runtime) { $0.runtimeProblem = "capstone 6" }
        XCTAssertEqual(broken.state, .failed)
        XCTAssertEqual(broken.chip, "REINSTALL APP")
        XCTAssertNil(broken.actionTitle)
        XCTAssertTrue(broken.detail.contains("capstone 6"))
    }

    func testKeys() {
        let ready = item(.keys)
        XCTAssertEqual(ready.state, .ready)
        XCTAssertEqual(ready.chip, "✓ IMPORTED")
        XCTAssertTrue(ready.detail.contains("3"), ready.detail)

        let missing = item(.keys) { $0.keys = nil }
        XCTAssertEqual(missing.state, .missing)
        XCTAssertEqual(missing.chip, "NOT IMPORTED")
        XCTAssertEqual(missing.actionTitle, "Choose file")

        let invalid = item(.keys) { $0.keys = nil; $0.keysError = "The keys file has no header_key." }
        XCTAssertEqual(invalid.state, .missing)
        XCTAssertEqual(invalid.detail, "The keys file has no header_key.")
    }

    func testLibrary() {
        let missing = item(.library) { $0.libraryWritable = nil }
        XCTAssertEqual(missing.state, .missing)
        XCTAssertEqual(missing.chip, "NOT CHOSEN")
        XCTAssertEqual(missing.actionTitle, "Choose folder")
        XCTAssertEqual(item(.library) { $0.libraryWritable = false }.state, .warning)
        XCTAssertEqual(item(.library) { $0.libraryWritable = false }.chip, "NOT WRITABLE")
        XCTAssertEqual(item(.library).state, .ready)
    }

    func testOverridesWin() {
        var f = facts()
        f.engine = .missing
        let items = SetupCheck.applying([.engine: .working("CLONING…")], to: SetupCheck.items(from: f))
        let engine = items.first { $0.id == .engine }!
        XCTAssertEqual(engine.state, .working)
        XCTAssertEqual(engine.chip, "CLONING…")
        XCTAssertNil(engine.actionTitle)
        XCTAssertEqual(items.first { $0.id == .xcode }!.state, .ready)
    }

    func testShouldReopenOnlyOnRegression() {
        var f = facts()
        f.metalVersion = "32023.917"
        f.keys = nil
        let current = SetupCheck.items(from: f)
        XCTAssertTrue(SetupCheck.shouldReopen(previous: [.metal: .ready], current: current))
        XCTAssertFalse(SetupCheck.shouldReopen(previous: [.keys: .missing], current: current))
        XCTAssertFalse(SetupCheck.shouldReopen(previous: [:], current: current))
    }

    // MARK: - Probe

    private final class FakeRunner: CommandRunning {
        var responses: [String: CommandResult] = [:]
        func run(_ executable: URL, _ arguments: [String],
                 environment: [String: String]?, currentDirectory: URL?) throws -> CommandResult {
            let key = ([executable.lastPathComponent] + arguments).joined(separator: " ")
            return responses.first { key.hasSuffix($0.key) }?.value ?? CommandResult(status: 0, stdout: "", stderr: "")
        }
    }

    private func probe(_ runner: FakeRunner, engine: URL, home: URL) -> SetupProbe {
        SetupProbe(runner: runner, toolchain: .resolve(runtime: nil, repo: engine), developerDir: nil,
                   engineFolder: engine, pinnedCommit: pin, certifiedMetal: "32023.921", allowUntested: false,
                   keyStore: KeyStore(directory: home.appendingPathComponent("keys")), libraryFolder: nil)
    }

    func testProbeFacts() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("SetupProbe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let engine = home.appendingPathComponent("nx native")
        let runner = FakeRunner()
        runner.responses["xcodebuild -version"] = CommandResult(status: 69, stdout: "", stderr: "license")
        runner.responses["metal --version"] = CommandResult(status: 0, stdout: "Apple metal version 32023.921 (metalfe-32023.921.6)\n", stderr: "")
        runner.responses["dotnet --list-sdks"] = CommandResult(status: 0, stdout: "10.0.401 [/usr/local/share/dotnet/sdk]\n", stderr: "")
        runner.responses["rev-parse HEAD"] = CommandResult(status: 0, stdout: pin + "\n", stderr: "")
        runner.responses["status --porcelain"] = CommandResult(status: 0, stdout: " M dm/gfx/nvn/dmsh_chain.h\n?? x/_build/a\n", stderr: "")

        XCTAssertEqual(probe(runner, engine: engine, home: home).facts().engine, .missing)

        try FileManager.default.createDirectory(at: engine, withIntermediateDirectories: true)
        XCTAssertEqual(probe(runner, engine: engine, home: home).facts().engine, .notACheckout)

        try FileManager.default.createDirectory(at: engine.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let facts = probe(runner, engine: engine, home: home).facts()
        XCTAssertEqual(facts.engine, .checkout(head: pin, dirty: false))
        XCTAssertEqual(facts.xcodeStatus, 69)
        XCTAssertEqual(facts.metalVersion, "32023.921")
        XCTAssertEqual(facts.dotnetSDKs, ["10.0.401 [/usr/local/share/dotnet/sdk]"])
        XCTAssertNil(facts.keys)
        XCTAssertNil(facts.libraryWritable)

        runner.responses["status --porcelain"] = CommandResult(status: 0, stdout: " M scripts/build_ipa_from_nsp.py\n", stderr: "")
        XCTAssertEqual(probe(runner, engine: engine, home: home).facts().engine, .checkout(head: pin, dirty: true))
    }
}
