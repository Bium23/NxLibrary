import XCTest
@testable import NXLibraryCore

final class SetupCheckTests: XCTestCase {
    func testKeysAreOptionalOnlyForAnEngineSupportingExtractedFolders() {
        var input = facts()
        input.keys = nil
        input.keysOptional = true
        let optional = SetupCheck.items(from: input).first { $0.id == .keys }
        XCTAssertEqual(optional?.state, .ready)
        XCTAssertEqual(optional?.chip, "OPTIONAL")
        input.keysOptional = false
        XCTAssertEqual(SetupCheck.items(from: input).first { $0.id == .keys }?.state, .missing)
    }
    private let pin = "af616f54652fa7f50a2e223ceed1d08a9bc83848"
    private let folder = URL(fileURLWithPath: "/Users/a b/nxnative")

    private func facts() -> SetupFacts {
        SetupFacts(xcodeStatus: 0, metalVersion: "32023.921", certifiedMetal: "32023.921", allowUntested: false,
                   dotnetSDKs: ["10.0.401 [/usr/local/share/dotnet/sdk]"],
                   engine: .checkout(head: pin, dirty: false), engineFolder: folder, pinnedCommit: pin,
                   runtimeProblem: nil,
                   keys: KeySummary(hasHeaderKey: true, applicationKeyGenerations: [0, 1, 2]), keysError: nil,
                   libraryReadable: true)
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

        let old = item(.xcode) { $0.xcodeVersion = "26.4" }
        XCTAssertEqual(old.state, .needsYou)
        XCTAssertEqual(old.chip, "UPDATE XCODE")
        XCTAssertEqual(old.actionTitle, "Open App Store")
        XCTAssertTrue(old.detail.contains("27.2"))
        XCTAssertEqual(item(.xcode) { $0.xcodeVersion = "27.2" }.state, .ready)
    }

    func testMetal() {
        let missing = item(.metal) { $0.metalVersion = nil }
        XCTAssertEqual(missing.state, .missing)
        XCTAssertEqual(missing.chip, "NOT INSTALLED")
        XCTAssertEqual(missing.actionTitle, "Install")

        let other = item(.metal) { $0.metalVersion = "32023.917" }
        XCTAssertEqual(other.state, .warning)
        XCTAssertEqual(other.chip, "NOT CERTIFIED")
        XCTAssertEqual(other.actionTitle, "Install 32023.921")

        let unknown = item(.metal) { $0.metalVersion = "32023.921"; $0.certifiedMetal = "32024.5" }
        XCTAssertEqual(unknown.state, .warning)
        XCTAssertEqual(unknown.chip, "WAITING FOR ENGINE")
        XCTAssertNil(unknown.actionTitle)
        XCTAssertTrue(unknown.detail.contains("still play"))

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
        XCTAssertNil(item(.dotnet).actionTitle)
        XCTAssertTrue(item(.dotnet).detail.contains("10.0.401"))
        let update = item(.dotnet) { $0.dotnetLatest = "10.0.404" }
        XCTAssertEqual(update.state, .ready)
        XCTAssertEqual(update.actionTitle, "Update to 10.0.404")
        XCTAssertNil(item(.dotnet) { $0.dotnetLatest = "10.0.401" }.actionTitle)
    }

    func testEngine() {
        let missing = item(.engine) { $0.engine = .missing }
        XCTAssertEqual(missing.state, .missing)
        XCTAssertEqual(missing.chip, "NOT INSTALLED")
        XCTAssertEqual(missing.actionTitle, "Clone")

        XCTAssertEqual(item(.engine).state, .ready)

        // After an NX Library update the engine here is older than the pin: an update, not an error.
        for behind in [true, nil] as [Bool?] {
            let update = item(.engine) { $0.engine = .checkout(head: "ee369f0", dirty: false); $0.engineBehind = behind }
            XCTAssertEqual(update.state, .warning, "still reopens Setup and runs with Install all")
            XCTAssertEqual(update.chip, "UPDATE READY")
            XCTAssertEqual(update.actionTitle, "Update")
            XCTAssertEqual(update.detail, "This NX Library uses nxnative af616f5; the engine here is at ee369f0. Update downloads it and switches to it. Games you built keep playing.")
        }
        // A checkout ahead of the pin (or on another branch) is moved back, said as such.
        let ahead = item(.engine) { $0.engine = .checkout(head: "ee369f0", dirty: false); $0.engineBehind = false }
        XCTAssertEqual(ahead.state, .warning)
        XCTAssertEqual(ahead.chip, "OTHER VERSION")
        XCTAssertEqual(ahead.actionTitle, "Switch")
        XCTAssertEqual(ahead.detail, "The engine here is at ee369f0, not the af616f5 this NX Library is tested with. Switch moves it to af616f5. Games you built keep playing.")

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
        let missing = item(.library) { $0.libraryReadable = nil }
        XCTAssertEqual(missing.state, .missing)
        XCTAssertEqual(missing.chip, "NOT CHOSEN")
        XCTAssertEqual(missing.actionTitle, "Choose folder")
        XCTAssertEqual(item(.library) { $0.libraryReadable = false }.state, .warning)
        XCTAssertEqual(item(.library) { $0.libraryReadable = false }.chip, "NOT READABLE")
        XCTAssertEqual(item(.library).state, .ready)
    }

    func testGameAppsFolderNeedsExplicitFirstSetupChoiceEvenWhenReadable() {
        let card = item(.library) {
            $0.libraryFolder = URL(fileURLWithPath: "/Users/a b/Applications")
            $0.libraryNeedsConfirmation = true
        }
        XCTAssertEqual(card.state, .needsYou)
        XCTAssertEqual(card.actionTitle, "Choose folder")
        XCTAssertTrue(card.detail.contains("/Users/a b/Applications"))
        XCTAssertTrue(card.isRequired)
    }

    func testGameFolderCardsLeadSetupAndShowDifferentPurposes() throws {
        var input = facts()
        input.libraryFolder = URL(fileURLWithPath: "/Volumes/Games/Mac apps")
        input.sourcesFolder = URL(fileURLWithPath: "/Volumes/Games/Packages")
        input.sourcesReadable = true
        let cards = SetupCheck.items(from: input)
        XCTAssertEqual(Array(cards.prefix(2)).map(\.id.rawValue), ["library", "sources"])
        let apps = try XCTUnwrap(cards.first { $0.id == .library })
        XCTAssertTrue(apps.about.contains(".app"))
        XCTAssertTrue(apps.about.contains("~/Applications"))
        XCTAssertTrue(apps.detail.contains("/Volumes/Games/Mac apps"))
        let files = try XCTUnwrap(cards.first { $0.id.rawValue == "sources" })
        XCTAssertTrue(files.detail.contains("/Volumes/Games/Packages"))
        for format in ["NSP", "XCI", "NSZ", "XCZ"] {
            XCTAssertTrue(files.about.contains(format), "Missing \(format)")
        }
        XCTAssertFalse(files.about.lowercased().contains("extracted"))

        input.extractedFoldersSupported = true
        let supported = try XCTUnwrap(SetupCheck.items(from: input).first { $0.id.rawValue == "sources" })
        XCTAssertTrue(supported.about.lowercased().contains("extracted folders"))
    }

    func testGameFilesFolderIsOptionalWhenUnchosenOrUnavailable() throws {
        for readable in [nil, false] as [Bool?] {
            var input = facts()
            input.sourcesReadable = readable
            if readable != nil { input.sourcesFolder = URL(fileURLWithPath: "/Volumes/Disconnected/Sources") }
            let cards = SetupCheck.items(from: input)
            let files = try XCTUnwrap(cards.first { $0.id.rawValue == "sources" })
            XCTAssertFalse(files.isRequired)
            XCTAssertEqual(files.state, readable == nil ? .ready : .warning)
            XCTAssertTrue(cards.filter(\.isRequired).allSatisfy { $0.state == .ready })
            XCTAssertFalse(SetupCheck.shouldReopen(previous: [files.id: .ready], current: cards))
            XCTAssertEqual(SetupCheck.automatic(cards, includeUpdates: true), [])
        }
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
        XCTAssertNil(engine.progress)

        f.dotnetSDKs = []
        let downloading = SetupCheck.applying([.dotnet: .working("DOWNLOADING…", progress: 0.25, detail: "50 of 200 MB")],
                                              to: SetupCheck.items(from: f)).first { $0.id == .dotnet }!
        XCTAssertEqual(downloading.chip, "DOWNLOADING… 25%")
        XCTAssertEqual(downloading.progress, 0.25)
        XCTAssertEqual(downloading.detail, "50 of 200 MB")
    }

    func testAutomaticActions() {
        var f = facts()
        XCTAssertEqual(SetupCheck.automatic(SetupCheck.items(from: f), includeUpdates: true), [])

        f.dotnetLatest = "10.0.404"
        XCTAssertEqual(SetupCheck.automatic(SetupCheck.items(from: f), includeUpdates: true), [.dotnet])
        XCTAssertEqual(SetupCheck.automatic(SetupCheck.items(from: f), includeUpdates: false), [])

        f.metalVersion = "32023.917"
        f.engine = .missing
        f.keys = nil
        XCTAssertEqual(SetupCheck.automatic(SetupCheck.items(from: f), includeUpdates: false), [.metal, .engine])
        // Metal comes through Xcode: nothing to try until Xcode is ready.
        f.xcodeVersion = "26.4"
        XCTAssertEqual(SetupCheck.automatic(SetupCheck.items(from: f), includeUpdates: false), [.engine])
        f.xcodeVersion = nil
        f.xcodeStatus = nil
        XCTAssertEqual(SetupCheck.automatic(SetupCheck.items(from: f), includeUpdates: false), [.engine])
        f.xcodeStatus = 0

        f.certifiedMetal = "32024.5"
        f.engine = .checkout(head: "ee369f0", dirty: true)
        f.dotnetSDKs = []
        let items = SetupCheck.applying([.dotnet: .working("DOWNLOADING…")], to: SetupCheck.items(from: f))
        XCTAssertEqual(SetupCheck.automatic(items, includeUpdates: true), [])
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
        var calls: [(executable: URL, arguments: [String])] = []
        func run(_ executable: URL, _ arguments: [String],
                 environment: [String: String]?, currentDirectory: URL?) throws -> CommandResult {
            calls.append((executable, arguments))
            let key = ([executable.lastPathComponent] + arguments).joined(separator: " ")
            return responses.first { key.hasSuffix($0.key) }?.value ?? CommandResult(status: 0, stdout: "", stderr: "")
        }
    }

    private func probe(_ runner: FakeRunner, engine: URL, home: URL,
                       library: URL? = nil, sources: URL? = nil, needsConfirmation: Bool = false) -> SetupProbe {
        SetupProbe(runner: runner, toolchain: .resolve(runtime: nil, repo: engine), developerDir: nil,
                   engineFolder: engine, pinnedCommit: pin, certifiedMetal: "32023.921", allowUntested: false,
                   keyStore: KeyStore(directory: home.appendingPathComponent("keys")), libraryFolder: library,
                   sourcesFolder: sources, libraryNeedsConfirmation: needsConfirmation)
    }

    func testReadOnlyGameAppsFolderIsReadyForDiscovery() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("SetupProbe-\(UUID().uuidString)")
        let library = home.appendingPathComponent("Existing game apps")
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.path)
            try? fm.removeItem(at: home)
        }
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: library.path)
        XCTAssertTrue(fm.isReadableFile(atPath: library.path))
        XCTAssertFalse(fm.isWritableFile(atPath: library.path))

        let facts = SetupProbe(runner: FakeRunner(), toolchain: .resolve(runtime: nil, repo: home),
                               developerDir: nil, engineFolder: home, pinnedCommit: pin,
                               certifiedMetal: "32023.921", allowUntested: false,
                               keyStore: KeyStore(directory: home.appendingPathComponent("keys")),
                               libraryFolder: library).facts()
        let card = SetupCheck.items(from: facts).first { $0.id == .library }
        XCTAssertEqual(card?.state, .ready)
    }

    func testProbeRejectsFilesAndKeepsUnavailableFolderPaths() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("SetupProbe-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let file = home.appendingPathComponent("file.nsp")
        try Data().write(to: file)
        let missing = home.appendingPathComponent("disconnected sources")

        let facts = probe(FakeRunner(), engine: home, home: home, library: file, sources: missing,
                          needsConfirmation: true).facts()
        XCTAssertEqual(facts.libraryReadable, false, "App discovery needs a directory, not a readable file")
        XCTAssertEqual(facts.libraryFolder, file)
        XCTAssertTrue(facts.libraryNeedsConfirmation)
        XCTAssertEqual(facts.sourcesReadable, false)
        XCTAssertEqual(facts.sourcesFolder, missing)
    }

    func testProbeReadsOptionalSourceFolderAndEngineCapabilities() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("SetupProbe-\(UUID().uuidString)")
        let scripts = home.appendingPathComponent("scripts")
        let sources = home.appendingPathComponent("sources")
        try fm.createDirectory(at: scripts, withIntermediateDirectories: true)
        try fm.createDirectory(at: sources, withIntermediateDirectories: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sources.path)
            try? fm.removeItem(at: home)
        }
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sources.path)
        let script = scripts.appendingPathComponent("build_ipa_from_nsp.py")
        try "import pack_dump\nparser.add_argument('--title-id')".write(to: script, atomically: true, encoding: .utf8)

        let facts = probe(FakeRunner(), engine: home, home: home, library: home, sources: sources).facts()
        XCTAssertEqual(facts.sourcesReadable, true)
        XCTAssertEqual(facts.sourcesFolder, sources)
        XCTAssertTrue(facts.extractedFoldersSupported)
        XCTAssertTrue(facts.keysOptional)
        let card = SetupCheck.items(from: facts).first { $0.id == .sources }
        XCTAssertEqual(card?.state, .ready)
        XCTAssertTrue(card?.about.contains("extracted folders") == true)

        try "parser.add_argument('--nsp')".write(to: script, atomically: true, encoding: .utf8)
        let legacy = probe(FakeRunner(), engine: home, home: home, library: home, sources: sources).facts()
        XCTAssertFalse(legacy.extractedFoldersSupported)
    }

    func testProbeWarnsForUnreadableGameAppsDirectory() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("SetupProbe-\(UUID().uuidString)")
        let library = home.appendingPathComponent("apps")
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.path)
            try? fm.removeItem(at: home)
        }
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: library.path)
        XCTAssertFalse(fm.isReadableFile(atPath: library.path))
        let facts = probe(FakeRunner(), engine: home, home: home, library: library).facts()
        XCTAssertEqual(facts.libraryReadable, false)
        XCTAssertEqual(SetupCheck.items(from: facts).first { $0.id == .library }?.state, .warning)
    }

    /// `-I` makes Python ignore PYTHONDONTWRITEBYTECODE, so each call passes `-B` itself: a bundled
    /// runtime that writes __pycache__ into the app breaks its code signature.
    func testProbeNeverWritesBytecodeIntoTheBundle() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("SetupProbe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = FakeRunner()
        let python = home.appendingPathComponent("Runtime/python/bin/python3")
        let toolchain = EngineToolchain(python: python, extraPath: [], isBundled: true)
        _ = SetupProbe(runner: runner, toolchain: toolchain, developerDir: nil, engineFolder: home,
                       pinnedCommit: pin, certifiedMetal: "32023.921", allowUntested: false,
                       keyStore: KeyStore(directory: home.appendingPathComponent("keys")), libraryFolder: nil).facts()
        let pythonCalls = runner.calls.filter { $0.executable == python }
        XCTAssertFalse(pythonCalls.isEmpty)
        for call in pythonCalls { XCTAssertTrue(call.arguments.contains("-B"), call.arguments.joined(separator: " ")) }
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
        XCTAssertNil(facts.xcodeVersion)
        XCTAssertEqual(facts.metalVersion, "32023.921")
        XCTAssertEqual(facts.dotnetSDKs, ["10.0.401 [/usr/local/share/dotnet/sdk]"])
        XCTAssertNil(facts.keys)
        XCTAssertNil(facts.libraryReadable)

        runner.responses["status --porcelain"] = CommandResult(status: 0, stdout: " M scripts/build_ipa_from_nsp.py\n", stderr: "")
        XCTAssertEqual(probe(runner, engine: engine, home: home).facts().engine, .checkout(head: pin, dirty: true))

        runner.responses["xcodebuild -version"] = CommandResult(status: 0, stdout: "Xcode 27.1\nBuild version 27A9275\n", stderr: "")
        XCTAssertEqual(probe(runner, engine: engine, home: home).facts().xcodeVersion, "27.1")
    }
}
