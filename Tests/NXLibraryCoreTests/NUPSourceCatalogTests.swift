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

    // The probe's output for a NUP with no base game (nxnative 777a5f6c: no base record and updates marked
    // standalone_update, or an empty base record): two updates and one DLC, no `base` line.
    private let updateOnlyProbe = "title 040074A01BF12000\nname 546573742047616d65\nupdate 393216 500\nupdate 458752 660\ndlc 040074A01BF13001 300\n"

    private func files(_ game: DetectedGame) -> [GameFileItem] {
        game.allSources.map {
            GameFileItem(url: $0.url, kind: $0.kind, titleId: String(format: "%016llX", $0.titleId),
                         versionString: $0.version.map { "v\($0)" }, sizeBytes: $0.sizeBytes, sourceLayout: $0.layout)
        }
    }

    func testNUPWithoutBaseOffersOnlyItsUpdates() throws {
        let nup = dir.appendingPathComponent("Bananza.nup")
        let game = try NUPSourceCatalog.parse(updateOnlyProbe, nup: nup, fileSize: 12,
                                              profiles: try repo().appendingPathComponent("dm/games"))
        XCTAssertNil(game.base, "no v0 to offer")
        XCTAssertTrue(game.hasGame)
        XCTAssertEqual(game.name, "Donkey Kong Bananza")
        XCTAssertEqual(game.updates.map(\.version), [393216, 458752])
        XCTAssertEqual(game.updates.map(\.sizeBytes), [12, 12], "the update stands in for the base: it carries the file's size")
        XCTAssertEqual(game.dlcs.map(\.titleId), [0x040074A01BF13001])
        XCTAssertEqual(game.totalSizeBytes, 12, "one file, counted once")
    }

    func testNUPWithNeitherBaseNorUpdateIsRefused() {
        for bad in ["title 040074A01BF12000\n", "title 040074A01BF12000\ndlc 040074A01BF13001 300\n"] {
            XCTAssertThrowsError(try NUPSourceCatalog.parse(bad, nup: dir.appendingPathComponent("G.nup"), fileSize: 1,
                                                            profiles: try repo().appendingPathComponent("dm/games"))) { error in
                XCTAssertEqual(error.localizedDescription,
                               EngineSourceError.invalidContainer("no base game or update").localizedDescription)
            }
        }
    }

    /// With no base the newest update is selected, one update always stays in (there is no v0 to fall back to), and the
    /// build is told the chosen version.
    func testSelectionOfANUPWithoutBase() throws {
        let game = try NUPSourceCatalog.parse(updateOnlyProbe, nup: dir.appendingPathComponent("Bananza.nup"), fileSize: 12,
                                              profiles: try repo().appendingPathComponent("dm/games"))
        let files = files(game)
        XCTAssertTrue(SourceSelection.isUpdateOnly(files))
        XCTAssertTrue(SourceSelection.hasGame(files))
        let selected = SourceSelection.initial(in: files)
        let newest = try XCTUnwrap(files.first { $0.versionString == "v458752" })
        let older = try XCTUnwrap(files.first { $0.versionString == "v393216" })
        let dlc = try XCTUnwrap(files.first { $0.kind == .dlc })
        XCTAssertEqual(selected, [newest.id, dlc.id])
        XCTAssertEqual(SourceSelection.versionForBuild(files.filter { selected.contains($0.id) }), "v458752")
        XCTAssertEqual(SourceSelection.uniqueSize(files.filter { selected.contains($0.id) }), 12)

        XCTAssertTrue(SourceSelection.isLocked(newest, in: files, selected: selected))
        XCTAssertFalse(SourceSelection.isLocked(older, in: files, selected: selected), "another update can be chosen")
        XCTAssertEqual(SourceSelection.toggling(newest.id, in: files, selected: selected), selected,
                       "the selected update cannot be cleared")
        let switched = SourceSelection.toggling(older.id, in: files, selected: selected)
        XCTAssertEqual(switched, [older.id, dlc.id])
        XCTAssertEqual(SourceSelection.versionForBuild(files.filter { switched.contains($0.id) }), "v393216")
        XCTAssertTrue(SourceSelection.hasGame(files.filter { switched.contains($0.id) }))

        // A rescan restores the chosen update, and falls back to the newest when it is gone.
        let rescanned = self.files(game)
        let restored = SourceSelection.restoredSelection(previous: files, selected: switched, current: rescanned)
        XCTAssertEqual(Set(rescanned.filter { restored.contains($0.id) }.compactMap(\.versionString)), ["v393216"])
        let gone = SourceSelection.restoredSelection(previous: files, selected: [dlc.id], current: rescanned)
        XCTAssertEqual(Set(rescanned.filter { gone.contains($0.id) }.compactMap(\.versionString)), ["v458752"])
    }

    /// An extracted dump with only updates follows the same rules: the newest update is selected and stays in.
    func testAnExtractedUpdateStandsInForTheBaseToo() {
        let older = GameFileItem(url: dir.appendingPathComponent("updates/65536"), kind: .update, versionString: "v65536",
                                 sizeBytes: 1, sourceLayout: .extracted)
        let newest = GameFileItem(url: dir.appendingPathComponent("updates/131072"), kind: .update, versionString: "v131072",
                                  sizeBytes: 1, sourceLayout: .extracted)
        let files = [older, newest]
        XCTAssertTrue(SourceSelection.isUpdateOnly(files))
        XCTAssertTrue(SourceSelection.hasGame(files))
        let selected = SourceSelection.initial(in: files)
        XCTAssertEqual(selected, [newest.id])
        XCTAssertTrue(SourceSelection.isLocked(newest, in: files, selected: selected))
        XCTAssertEqual(SourceSelection.versionForBuild(files.filter { selected.contains($0.id) }), "v131072")
    }

    func testOnlyANUPUpdateStandsInForTheBase() {
        let nsp = GameFileItem(url: dir.appendingPathComponent("Update.nsp"), kind: .update, versionString: "v65536", sizeBytes: 1)
        XCTAssertFalse(SourceSelection.hasGame([nsp]), "the engine needs the base game beside an NSP update")
        XCTAssertFalse(SourceSelection.isUpdateOnly([nsp]))
        XCTAssertFalse(SourceSelection.isLocked(nsp, in: [nsp], selected: [nsp.id]))
        let dlc = GameFileItem(url: dir.appendingPathComponent("G.nup"), kind: .dlc, sizeBytes: 1, sourceLayout: .container)
        XCTAssertFalse(SourceSelection.hasGame([dlc]))
    }

    func testNUPWithoutBaseAttachesAndBuildsTheChosenUpdate() throws {
        let nup = try write("Bananza.nup", "NUP\u{1}")
        let game = try NUPSourceCatalog.parse(updateOnlyProbe, nup: nup, fileSize: 4,
                                              profiles: try repo().appendingPathComponent("dm/games"))
        let workspace = try WorkspaceManager(root: dir.appendingPathComponent("workspaces")).makeWorkspace(for: game, mode: .staged)
        XCTAssertEqual(workspace.links.map(\.lastPathComponent), ["Bananza.nup"])

        var ported = PortedGame(name: game.name, url: workspace.directory, platform: .macApp, sizeBytes: 4,
                                modificationDate: .distantPast)
        ported.sources = files(game).filter { $0.versionString != "v393216" }
        XCTAssertTrue(GameResourceState.sourcesAvailable(for: ported), "the update is the game: sources are attached")
        XCTAssertFalse(LibraryPresentation(game: ported, metadata: nil, totalPlaytime: 0, lastPlayed: nil).sourcesDetached)

        let repo = URL(fileURLWithPath: "/tmp/engine")
        let command = BuildCommandBuilder.make(repo: repo, toolchain: EngineToolchain.resolve(runtime: nil, repo: repo),
            workspace: workspace.directory, keys: nil, output: URL(fileURLWithPath: "/tmp/Game.app"),
            developerDir: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer"),
            titleId: "040074A01BF12000", packageVersion: SourceSelection.versionForBuild(ported.sources))
        let flag = try XCTUnwrap(command.arguments.firstIndex(of: "-p"))
        XCTAssertEqual(command.arguments[flag + 1], "v458752", "never v0: the NUP has none")
        XCTAssertFalse(command.arguments.contains("-k"), "a NUP needs no keys")
    }

    func testWorkspaceLinksTheFileOnce() throws {
        let nup = try write("Bananza.nup", "NUP\u{1}")
        let game = try NUPSourceCatalog.parse(probe, nup: nup, fileSize: 4, profiles: try repo().appendingPathComponent("dm/games"))
        let workspace = try WorkspaceManager(root: dir.appendingPathComponent("workspaces")).makeWorkspace(for: game, mode: .staged)
        XCTAssertEqual(workspace.links.map(\.lastPathComponent), ["Bananza.nup"])
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: workspace.links[0].path), nup.path)
    }
}
