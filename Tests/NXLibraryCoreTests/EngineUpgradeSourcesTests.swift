import XCTest
@testable import NXLibraryCore

final class EngineUpgradeSourcesTests: XCTestCase {
    func testMultipleTitlesNeedAnExplicitChoiceButRescansKeepTheChosenTitle() {
        let titles = ["0100000000010000", "0100000000020000"]
        XCTAssertNil(SourceSelection.initialTitleID(available: titles, previous: nil))
        XCTAssertNil(SourceSelection.initialTitleID(available: titles, previous: "other"))
        XCTAssertEqual(SourceSelection.initialTitleID(available: titles, previous: titles[1]), titles[1])
        XCTAssertEqual(SourceSelection.initialTitleID(available: [titles[0]], previous: nil), titles[0])
    }

    private func choice(_ name: String, kind: SourceKind, version: String? = nil) -> GameFileItem {
        GameFileItem(url: URL(fileURLWithPath: "/tmp/\(name).nsp"), kind: kind,
                     titleId: "0100000000010000", versionString: version, sizeBytes: 1)
    }

    func testKeyRescanPreservesChosenUpdateAndExcludedDLCWithNewItemIDs() {
        let old = [choice("base", kind: .base), choice("update1", kind: .update, version: "v1"),
                   choice("update2", kind: .update, version: "v2"), choice("dlc", kind: .dlc)]
        let current = [choice("base", kind: .base), choice("update1", kind: .update, version: "1"),
                       choice("update2", kind: .update, version: "2"), choice("dlc", kind: .dlc)]
        let restored = SourceSelection.restoredSelection(previous: old, selected: [old[0].id, old[1].id], current: current)
        XCTAssertEqual(restored, [current[0].id, current[1].id])
        XCTAssertEqual(SourceSelection.versionForBuild(current.filter { restored.contains($0.id) }), "v1")
    }

    func testKeyRescanKeepsTheUsersNoUpdateChoiceWhenMoreVersionsBecomeReadable() {
        let old = [choice("base", kind: .base), choice("update1", kind: .update, version: "v1")]
        let current = [choice("base", kind: .base), choice("update1", kind: .update, version: "v1"),
                       choice("newer", kind: .update, version: "v2")]
        XCTAssertEqual(SourceSelection.restoredSelection(previous: old, selected: [old[0].id], current: current),
                       [current[0].id])
    }

    func testKeyRescanRecognisesPreviouslyChosenContentAfterReadingItsVersion() {
        let old = [choice("base", kind: .base), choice("update", kind: .update)]
        let current = [choice("base", kind: .base), choice("update", kind: .update, version: "v65536")]
        XCTAssertEqual(SourceSelection.restoredSelection(previous: old, selected: Set(old.map(\.id)), current: current),
                       Set(current.map(\.id)))
    }

    private let title: UInt64 = 0x0400000000000000

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func version(_ folder: URL, title: UInt64) throws {
        let exefs = folder.appendingPathComponent("exefs")
        try FileManager.default.createDirectory(at: exefs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("romfs"), withIntermediateDirectories: true)
        var bytes = Data(repeating: 0, count: 0x100)
        bytes.replaceSubrange(0..<4, with: Data("META".utf8))
        bytes[0x70] = 0x80; bytes[0x74] = 0x20
        bytes.replaceSubrange(0x80..<0x84, with: Data("ACI0".utf8))
        for i in 0..<8 { bytes[0x90 + i] = UInt8(truncatingIfNeeded: title >> (8 * i)) }
        try bytes.write(to: exefs.appendingPathComponent("main.npdm"))
        try Data("synthetic code".utf8).write(to: exefs.appendingPathComponent("main"))
        try Data("synthetic data".utf8).write(to: folder.appendingPathComponent("romfs/data"))
    }

    func testExtractedFolderScansAndStagesOnlySelectedVersionsWithoutCopyingSources() throws {
        let root = try temporaryFolder()
        let dump = root.appendingPathComponent("dump")
        try version(dump.appendingPathComponent("base"), title: title)
        try version(dump.appendingPathComponent("updates/65536"), title: title)
        try version(dump.appendingPathComponent("updates/131072"), title: title)
        let dlc = dump.appendingPathComponent("dlc/0400000000001001/0/romfs")
        try FileManager.default.createDirectory(at: dlc, withIntermediateDirectories: true)
        try Data("dlc".utf8).write(to: dlc.appendingPathComponent("data"))
        let profiles = root.appendingPathComponent("profiles")
        let profile = profiles.appendingPathComponent(String(format: "%016llX", title))
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data("name\tSynthetic title\n".utf8).write(to: profile.appendingPathComponent("game.tsv"))
        let game = try ExtractedSourceCatalog(profiles: profiles).scan(folder: dump)
        XCTAssertEqual(game.name, "Synthetic title")
        XCTAssertEqual(game.updates.map(\.version), [65536, 131072])
        XCTAssertEqual(game.dlcs.count, 1)
        XCTAssertEqual(game.base?.layout, .extracted)
        let picked = DetectedGame(baseTitleId: title, name: game.name, base: game.base,
                                  updates: [game.updates[0]], dlcs: game.dlcs)
        let workspace = try WorkspaceManager(root: root.appendingPathComponent("work")).makeWorkspace(for: picked, mode: .staged)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: workspace.directory.appendingPathComponent("base").path), dump.appendingPathComponent("base").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.directory.appendingPathComponent("updates/65536/exefs/main").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.directory.appendingPathComponent("updates/131072").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.directory.appendingPathComponent("dlc/0400000000001001/0/romfs/data").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dump.appendingPathComponent("0400000000000000_build").path))
        var withoutDLC = picked
        withoutDLC.dlcs = []
        _ = try WorkspaceManager(root: root.appendingPathComponent("work")).makeWorkspace(for: withoutDLC, mode: .staged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.directory.appendingPathComponent("dlc/0400000000001001").path),
                       "Empty DLC containers are invalid inputs to upstream pack_dump.scan")
    }

    func testExtractedFolderRejectsMissingProfileAndMismatchedUpdate() throws {
        let root = try temporaryFolder()
        try version(root.appendingPathComponent("base"), title: title)
        let catalog = ExtractedSourceCatalog(profiles: root.appendingPathComponent("profiles"))
        XCTAssertThrowsError(try catalog.scan(folder: root))
        let profile = root.appendingPathComponent("profiles/0400000000000000")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data("name\tSynthetic\n".utf8).write(to: profile.appendingPathComponent("game.tsv"))
        try version(root.appendingPathComponent("updates/65536"), title: title + 0x2000)
        XCTAssertThrowsError(try catalog.scan(folder: root))
    }

    func testMergedPackageExposesBothGamesAndCountsPhysicalFileOnce() throws {
        let root = try temporaryFolder()
        let file = root.appendingPathComponent("two-games.xci")
        try Data("synthetic".utf8).write(to: file)
        let games = try SourceCatalog().scan(files: [file], contentsReader: { _ in [
            PackageContent(kind: .base, titleId: 0x0100000000000000, version: 0),
            PackageContent(kind: .update, titleId: 0x0100000000000800, version: 65536),
            PackageContent(kind: .dlc, titleId: 0x0100000000001001, version: 0),
            PackageContent(kind: .base, titleId: 0x0100000000002000, version: 0)
        ] })
        XCTAssertEqual(games.count, 2)
        let first = try XCTUnwrap(games.first { $0.baseTitleId == 0x0100000000000000 })
        XCTAssertEqual(first.allSources.count, 3)
        XCTAssertEqual(first.base?.requiresTitleSelection, true)
        XCTAssertEqual(first.totalSizeBytes, 9)
        let workspace = try WorkspaceManager(root: root.appendingPathComponent("work")).makeWorkspace(for: first, mode: .staged)
        XCTAssertEqual(workspace.links.count, 1)
    }

    func testBundledDLCStaysIncludedAndUpdateSelectionDeterminesBuildVersion() {
        let file = URL(fileURLWithPath: "/tmp/merged.nsp")
        let base = GameFileItem(url: file, kind: .base, sizeBytes: 100)
        let update = GameFileItem(url: file, kind: .update, versionString: "v65536", sizeBytes: 100)
        let dlc = GameFileItem(url: file, kind: .dlc, sizeBytes: 100)
        let files = [base, update, dlc]
        let initial = SourceSelection.initial(in: files)
        XCTAssertEqual(initial, Set(files.map(\.id)))
        XCTAssertTrue(SourceSelection.isLocked(dlc, in: files, selected: initial))
        XCTAssertEqual(SourceSelection.toggling(dlc.id, in: files, selected: initial), initial)
        let baseOnly = SourceSelection.toggling(update.id, in: files, selected: initial)
        let selected = files.filter { baseOnly.contains($0.id) }
        XCTAssertEqual(SourceSelection.versionForBuild(selected), "v0")
        XCTAssertEqual(SourceSelection.uniqueSize(selected), 100)
        XCTAssertTrue(baseOnly.contains(dlc.id))
    }

    func testPackageContentParsingValidatesIdentityAndDoesNotTreatLogLinesAsContent() throws {
        let rows = try PackageContent.parse("note: probe ready\ncontent Application 0100000000000000 0\ncontent Patch 0100000000000800 65536\n")
        XCTAssertEqual(rows.count, 2)
        XCTAssertThrowsError(try PackageContent.parse("content Application ../bad 0\n"))
    }

    func testLegacySourceDecodesAsPackageAndExtractedLayoutRoundTrips() throws {
        let file = GameFileItem(url: URL(fileURLWithPath: "/tmp/base.nsp"), kind: .base, sizeBytes: 1)
        let legacy = try JSONEncoder().encode(file)
        XCTAssertEqual(try JSONDecoder().decode(GameFileItem.self, from: legacy).layout, .package)
        var extracted = file
        extracted.sourceLayout = .extracted
        let restored = try JSONDecoder().decode(GameFileItem.self, from: JSONEncoder().encode(extracted))
        XCTAssertEqual(restored.layout, .extracted)
        XCTAssertFalse(SourceSelection.requiresKeys([restored]))
        XCTAssertTrue(SourceSelection.requiresKeys([file]))
    }

    func testRestagingRemovesDeselectedLinksAndKeepsTheCacheAndOriginals() throws {
        let root = try temporaryFolder()
        let baseURL = root.appendingPathComponent("base.nsp")
        let updateURL = root.appendingPathComponent("update.nsp")
        try Data("base".utf8).write(to: baseURL)
        try Data("update".utf8).write(to: updateURL)
        let base = DetectedSource(url: baseURL, kind: .base, titleId: title, sizeBytes: 4)
        let update = DetectedSource(url: updateURL, kind: .update, titleId: title + 0x800, version: 65536, sizeBytes: 6)
        let manager = WorkspaceManager(root: root.appendingPathComponent("work"))
        var game = DetectedGame(baseTitleId: title, name: "Synthetic", base: base, updates: [update])
        let first = try manager.makeWorkspace(for: game, mode: .staged)
        try Data("cache".utf8).write(to: first.buildCache.appendingPathComponent("marker"))
        game.updates = []
        let second = try manager.makeWorkspace(for: game, mode: .staged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.directory.appendingPathComponent("update.nsp").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: updateURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.buildCache.appendingPathComponent("marker").path))
    }

    func testOneUnreadablePackageDoesNotHideOtherGames() throws {
        let root = try temporaryFolder()
        let valid = root.appendingPathComponent("Synthetic [0100000000000000].xci")
        let bad = root.appendingPathComponent("broken.nsp")
        var skipped: [URL] = []
        let games = try SourceCatalog().scan(files: [bad, valid], skippingUnreadable: true,
            onUnreadable: { url, _ in skipped.append(url) }, contentsReader: { url in
                if url == bad { throw EngineSourceError.invalidPackage }
                return []
            })
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(skipped, [bad])
        XCTAssertThrowsError(try SourceCatalog().scan(files: [bad], skippingUnreadable: true))
    }

    func testMergedSourceCannotBeBuiltWithAnEngineThatCannotSelectItsTitle() throws {
        var file = GameFileItem(url: URL(fileURLWithPath: "/tmp/merged.xci"), kind: .base, sizeBytes: 1)
        file.requiresTitleSelection = true
        let restored = try JSONDecoder().decode(GameFileItem.self, from: JSONEncoder().encode(file))
        XCTAssertFalse(SourceSelection.supported([restored], titleSelection: false, extractedFolders: false))
        XCTAssertTrue(SourceSelection.supported([restored], titleSelection: true, extractedFolders: false))
    }

    func testMetadataBridgeRunsWithTheUpstreamReaderContract() throws {
        let root = try temporaryFolder()
        let scripts = root.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        let fixture = #"""
import contextlib
def is_merged(path): return path.name == 'merged.nsp'
def configure_dotnet(environment): pass
@contextlib.contextmanager
def package_title_reader(repo, keys, environment):
    assert keys.name == 'private-key-input'
    class Reader:
        def contents(self, path):
            return [('Application', 0x0100000000000000, 0), ('Patch', 0x0100000000000800, 65536)]
    print('probe progress must not reach the parser')
    yield Reader()
"""#
        try Data(fixture.utf8).write(to: scripts.appendingPathComponent("build_ipa_from_nsp.py"))
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { throw XCTSkip("system Python unavailable") }
        let toolchain = EngineToolchain(python: python, extraPath: [], isBundled: false)
        let reader = EnginePackageReader(repo: root, toolchain: toolchain,
            keys: root.appendingPathComponent("private-key-input"),
            developerDir: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer"))
        XCTAssertEqual(try reader.contents(of: root.appendingPathComponent("merged.nsp"), alreadyIdentified: true).count, 2)
        XCTAssertEqual(try reader.contents(of: root.appendingPathComponent("plain.nsp"), alreadyIdentified: true), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: scripts.appendingPathComponent("__pycache__").path))
    }
}
