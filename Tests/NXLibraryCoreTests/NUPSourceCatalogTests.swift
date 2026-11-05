import XCTest
@testable import NXLibraryCore

final class NUPSourceCatalogTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private final class Runner: CommandRunning {
        var result: CommandResult
        var arguments: [String] = []
        init(_ result: CommandResult) { self.result = result }
        func run(_ executable: URL, _ arguments: [String], environment: [String: String]?, currentDirectory: URL?) throws -> CommandResult {
            self.arguments = arguments
            return result
        }
    }

    private func write(_ name: String, _ bytes: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(bytes.utf8).write(to: url)
        return url
    }

    /// An engine folder with a profile for Bananza.
    private func repo(profileName: String? = "Donkey Kong Bananza") throws -> URL {
        let repo = dir.appendingPathComponent("engine")
        let profile = repo.appendingPathComponent("dm/games/040074A01BF12000")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let text = "id\t040074A01BF12000\n" + (profileName.map { "name\t\($0)\n" } ?? "")
        try text.write(to: profile.appendingPathComponent("game.tsv"), atomically: true, encoding: .utf8)
        return repo
    }

    private func catalog(_ repo: URL, _ runner: Runner) -> NUPSourceCatalog {
        NUPSourceCatalog(repo: repo, toolchain: EngineToolchain(python: URL(fileURLWithPath: "/usr/bin/false"), extraPath: [], isBundled: true),
                         developerDir: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer"), runner: runner)
    }

    // The probe's output for a NUP with the base game, update v458752 named by its NACP, and one DLC
    // (what upstream's pack_nup.scan gives for the container dm/tools/tests/test_nsp_nup.py writes).
    private let probe = "title 040074A01BF12000\nname 546573742047616d65\nbase 660\nupdate 458752 660\ndlc 040074A01BF13001 300\n"

    func testNUPIsRecognizedByItsMagic() throws {
        XCTAssertTrue(NUPSourceCatalog.isNUP(try write("Game.nup", "NUP\u{1}rest")))
        XCTAssertFalse(NUPSourceCatalog.isNUP(try write("Other.nup", "PFS0")))
        XCTAssertFalse(NUPSourceCatalog.isNUP(try write("Game.nsp", "NUP\u{1}")))
        XCTAssertFalse(NUPSourceCatalog.isNUP(try write("._Game.nup", "NUP\u{1}")))
    }

    func testFolderContainerIsItsOneNUPWithoutPackages() throws {
        let nup = try write("Game.nup", "NUP\u{1}")
        XCTAssertEqual(NUPSourceCatalog.container(in: dir)?.lastPathComponent, nup.lastPathComponent)
        _ = try write("Game.nsp", "PFS0")
        XCTAssertNil(NUPSourceCatalog.container(in: dir), "a package beside it makes it a package folder")
    }

    func testTwoNUPsAreNotOneGame() throws {
        _ = try write("A.nup", "NUP\u{1}")
        _ = try write("B.nup", "NUP\u{1}")
        XCTAssertNil(NUPSourceCatalog.container(in: dir))
    }

    func testScanListsEveryPackageOfTheFile() throws {
        let nup = try write("Bananza.nup", "NUP\u{1}contents")
        let runner = Runner(CommandResult(status: 0, stdout: probe, stderr: ""))
        let game = try catalog(try repo(), runner).scan(nup: nup)
        XCTAssertEqual(runner.arguments.last, nup.path)
        XCTAssertEqual(game.baseTitleId, 0x040074A01BF12000)
        XCTAssertEqual(game.name, "Donkey Kong Bananza", "the profile's name, as for a dump")
        XCTAssertEqual(game.base?.layout, .container)
        XCTAssertEqual(game.base?.sizeBytes, 12, "the base carries the file's size")
        XCTAssertEqual(game.updates.map(\.version), [458752])
        XCTAssertEqual(game.updates.first?.titleId, 0x040074A01BF12800)
        XCTAssertEqual(game.dlcs.map(\.titleId), [0x040074A01BF13001])
        XCTAssertTrue(game.allSources.allSatisfy { $0.url == nup && $0.layout == .container })
        XCTAssertEqual(game.totalSizeBytes, 12, "one file, counted once")
    }

    func testProfileWithoutANameUsesTheContainersNACP() throws {
        let game = try NUPSourceCatalog.parse(probe, nup: dir.appendingPathComponent("G.nup"), fileSize: 1,
                                              profiles: try repo(profileName: nil).appendingPathComponent("dm/games"))
        XCTAssertEqual(game.name, "Test Game")
    }

    func testGameWithoutProfileIsRefusedAsADumpIs() throws {
        let engine = dir.appendingPathComponent("empty-engine")
        XCTAssertThrowsError(try NUPSourceCatalog.parse(probe, nup: dir.appendingPathComponent("G.nup"), fileSize: 1,
                                                        profiles: engine.appendingPathComponent("dm/games"))) { error in
            XCTAssertEqual(error.localizedDescription, EngineSourceError.missingProfile("040074A01BF12000").localizedDescription)
        }
    }

    func testAnEngineWithProvisionalProfilesTakesTheGameByItsNACPName() throws {
        let engine = dir.appendingPathComponent("empty-engine")
        let game = try NUPSourceCatalog.parse(probe, nup: dir.appendingPathComponent("G.nup"), fileSize: 1,
                                              profiles: engine.appendingPathComponent("dm/games"), provisional: true)
        XCTAssertEqual(game.name, "Test Game")
        XCTAssertEqual(game.baseTitleId, 0x040074A01BF12000)
    }

    func testProvisionalProfilesAreReadFromTheEngine() {
        let old = EngineSourceCapabilities(script: "'--title-id'\nimport pack_dump\nimport pack_nup\n")
        XCTAssertTrue(old.nupContainers)
        XCTAssertFalse(old.provisionalNUP)
        XCTAssertFalse(old.provisionalDumps)
        let new = EngineSourceCapabilities(script: "'--title-id'\nimport pack_dump\nimport pack_nup\ndef survey_nup(\ndef survey_dump(\n")
        XCTAssertTrue(new.provisionalNUP)
        XCTAssertTrue(new.provisionalDumps)
        XCTAssertFalse(EngineSourceCapabilities(script: "def survey_nup(\n").provisionalNUP, "only with NUP support")
    }

    func testEngineErrorReachesThePlayer() throws {
        let nup = try write("Broken.nup", "NUP\u{1}")
        let runner = Runner(CommandResult(status: 1, stdout: "", stderr: "Broken.nup: not a NUP (too short)\n"))
        XCTAssertThrowsError(try catalog(try repo(), runner).scan(nup: nup)) { error in
            XCTAssertEqual(error.localizedDescription, "The NUP file could not be read: Broken.nup: not a NUP (too short).")
        }
    }

    func testMalformedProbeOutputIsRefused() {
        for bad in ["name 00\nbase 1\n", "title 040074A01BF12001\nbase 1\n", "title 040074A01BF12000\n",
                    "title 040074A01BF12000\nbase 1\ndlc 0100000000000001 5\n"] {
            XCTAssertThrowsError(try NUPSourceCatalog.parse(bad, nup: dir.appendingPathComponent("G.nup"), fileSize: 1,
                                                            profiles: dir), bad)
        }
    }

    /// Every package of the file shares it: the base keeps its DLC locked in, one update is chosen at a time, and the
    /// build is told the version (`--package`).
    func testSelectionFollowsWhatTheEngineBuilds() throws {
        let nup = dir.appendingPathComponent("Bananza.nup")
        let game = try NUPSourceCatalog.parse(probe, nup: nup, fileSize: 12, profiles: try repo().appendingPathComponent("dm/games"))
        let files = game.allSources.map {
            GameFileItem(url: $0.url, kind: $0.kind, titleId: String(format: "%016llX", $0.titleId),
                         versionString: $0.version.map { "v\($0)" }, sizeBytes: $0.sizeBytes, sourceLayout: $0.layout)
        }
        let selected = SourceSelection.initial(in: files)
        XCTAssertEqual(selected.count, 3)
        let dlc = try XCTUnwrap(files.first { $0.kind == .dlc })
        XCTAssertTrue(SourceSelection.isLocked(dlc, in: files, selected: selected), "the engine packs every DLC in the file")
        let update = try XCTUnwrap(files.first { $0.kind == .update })
        let baseOnly = SourceSelection.toggling(update.id, in: files, selected: selected)
        XCTAssertEqual(SourceSelection.versionForBuild(files.filter { baseOnly.contains($0.id) }), "v0")
        XCTAssertEqual(SourceSelection.versionForBuild(files.filter { selected.contains($0.id) }), "v458752")
        XCTAssertFalse(SourceSelection.requiresKeys(files))
        XCTAssertFalse(SourceSelection.supported(files, titleSelection: true, extractedFolders: true))
        XCTAssertTrue(SourceSelection.supported(files, titleSelection: true, extractedFolders: true, nupContainers: true))
    }

    func testWorkspaceLinksTheFileOnce() throws {
        let nup = try write("Bananza.nup", "NUP\u{1}")
        let game = try NUPSourceCatalog.parse(probe, nup: nup, fileSize: 4, profiles: try repo().appendingPathComponent("dm/games"))
        let workspace = try WorkspaceManager(root: dir.appendingPathComponent("workspaces")).makeWorkspace(for: game, mode: .staged)
        XCTAssertEqual(workspace.links.map(\.lastPathComponent), ["Bananza.nup"])
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: workspace.links[0].path), nup.path)
    }
}
