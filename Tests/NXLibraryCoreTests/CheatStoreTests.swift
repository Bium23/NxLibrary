import XCTest
@testable import NXLibraryCore

final class CheatStoreTests: XCTestCase {
    private var dir: URL!
    private var folder: URL { dir.appendingPathComponent("cheats") }
    private let tid = "0100000000010000"
    private let build = "B424BE150A8E7D78"
    private var allowed = true
    private var trashed: [String] = []

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("CheatStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        allowed = true
        trashed = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: dir)
    }

    private func store(build: String? = nil) -> CheatStore {
        CheatStore(folder: folder, titleID: tid, buildID: build ?? self.build,
                   canWrite: { [unowned self] in allowed },
                   trash: { [unowned self] url in trashed.append(url.lastPathComponent); try FileManager.default.removeItem(at: url) })
    }

    private let abc = Data("[A]\n04000000 00004000 00000001\n[B]\n04000000 00004004 00000001\n{M}\n04000000 00004008 00000001\n[X]\n04000000 0000400C 00000001\n[X]\n04000000 00004010 00000001\n[Note]\n".utf8)

    private func read(_ name: String) -> String? {
        try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }

    private func folderSnapshot() -> [String: Data] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Dictionary(uniqueKeysWithValues: names.map { ($0, (try? Data(contentsOf: folder.appendingPathComponent($0))) ?? Data()) })
    }

    func testInstallStartsAllOff() throws {
        try store().install(abc, replacing: false)
        let state = store().state()
        XCTAssertEqual(state.file?.switches.map(\.name), ["A", "B", "X", "X #2"])
        XCTAssertEqual(state.enabled, [])
        XCTAssertTrue(state.hasEnabledFile)
        XCTAssertEqual(read("\(build).enabled"), "")
        XCTAssertEqual(state.onCount, 0)
        XCTAssertTrue(state.masterOn)
    }

    func testReplaceKeepsOnNamesThatSurvive() throws {
        try store().install(abc, replacing: false)
        try store().setEnabled(["A", "B"])
        try store().install(Data("[A]\n04000000 00004000 00000002\n[C]\n04000000 00004004 00000002\n".utf8), replacing: true)
        XCTAssertEqual(store().state().enabled, ["A"])
        XCTAssertEqual(read("\(build).enabled"), "A\n")
    }

    /// hle_cheats.c states_save: one key per line in file order; masters, labels, one-pass cheats never saved.
    func testEnabledFileFormat() throws {
        try store().install(abc, replacing: false)
        try store().setEnabled(["X #2", "A", "M", "Note", "Nope"])
        XCTAssertEqual(read("\(build).enabled"), "A\nX #2\n")
        XCTAssertEqual(store().state().onCount, 2)
    }

    /// hle_cheats.c states_read: a line naming a duplicate without its number turns on the next entry of that name.
    func testOlderEnabledLinesReadLikeTheEngine() throws {
        try store().install(abc, replacing: false)
        try Data("X\nX\n".utf8).write(to: folder.appendingPathComponent("\(build).enabled"))
        XCTAssertEqual(store().state().enabled, ["X", "X #2"])
    }

    func testMasterSwitchFile() throws {
        try store().install(abc, replacing: false)
        try store().setMaster(on: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".cheats-off-\(tid)").path))
        XCTAssertFalse(store().state().masterOn)
        try store().setMaster(on: true)
        XCTAssertTrue(store().state().masterOn)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".cheats-off-\(tid)").path))
    }

    func testSafeModeFlagIsReadNeverWritten() throws {
        try store().install(abc, replacing: false)
        let flag = folder.appendingPathComponent(".cheats-running-\(tid)")
        try Data("pid 1".utf8).write(to: flag)
        XCTAssertTrue(store().state().safeModePending)
        try store().setEnabled(["A"])
        try store().setMaster(on: false)
        try store().setMaster(on: true)
        try store().turnAllOff()
        try store().install(abc, replacing: true)
        XCTAssertEqual(try Data(contentsOf: flag), Data("pid 1".utf8))
    }

    /// hle_cheats.c scan_dirs: the flat folder first, then atmosphere/contents/<tid>/cheats and contents/<tid>/cheats.
    func testReadsAtmosphereTree() throws {
        for tree in ["atmosphere/contents/\(tid)/cheats", "contents/\(tid)/cheats"] {
            try? FileManager.default.removeItem(at: folder)
            let sub = folder.appendingPathComponent(tree)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try abc.write(to: sub.appendingPathComponent("\(build.lowercased()).txt"))
            XCTAssertEqual(store().state().file?.switches.count, 4, tree)
        }
    }

    /// Review Focus 2: a game update changes the build ID; the old file is another build's.
    func testUpdatedGameSeesOldFileAsOtherBuild() throws {
        try store(build: "AAAAAAAAAAAAAAAA").install(abc, replacing: false)
        try store(build: "AAAAAAAAAAAAAAAA").setEnabled(["A"])
        let state = store(build: "BBBBBBBBBBBBBBBB").state()
        XCTAssertNil(state.file)
        XCTAssertEqual(state.otherBuilds, ["AAAAAAAAAAAAAAAA"])
        XCTAssertEqual(state.onCount, 0)
        XCTAssertEqual(state.enabled, [])
    }

    /// Review Focus 5: the game started between reading and writing.
    func testWritesRefuseWhenNotAllowed() throws {
        try store().install(abc, replacing: false)
        let before = folderSnapshot()
        allowed = false
        XCTAssertThrowsError(try store().install(abc, replacing: true)) { XCTAssertEqual($0 as? CheatStoreError, .notAllowed) }
        XCTAssertThrowsError(try store().setEnabled(["A"])) { XCTAssertEqual($0 as? CheatStoreError, .notAllowed) }
        XCTAssertThrowsError(try store().setMaster(on: false)) { XCTAssertEqual($0 as? CheatStoreError, .notAllowed) }
        XCTAssertThrowsError(try store().turnAllOff()) { XCTAssertEqual($0 as? CheatStoreError, .notAllowed) }
        XCTAssertThrowsError(try store().remove(build: build)) { XCTAssertEqual($0 as? CheatStoreError, .notAllowed) }
        XCTAssertEqual(folderSnapshot(), before)
    }

    func testWritesAreAtomic() throws {
        try store().install(abc, replacing: false)
        try store().setEnabled(["A"])
        XCTAssertEqual(Set(folderSnapshot().keys), ["\(build).txt", "\(build).enabled"], "no temporary file left")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        XCTAssertThrowsError(try store().setEnabled(["B"])) {
            guard case .writeFailed = $0 as? CheatStoreError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(read("\(build).enabled"), "A\n")
    }

    func testRemoveGoesToTrash() throws {
        try store().install(abc, replacing: false)
        try Data("name\n".utf8).write(to: folder.appendingPathComponent("\(build).meta.tsv"))
        try Data("A\t1\n".utf8).write(to: folder.appendingPathComponent("\(build).values"))
        try store().remove(build: build)
        XCTAssertEqual(Set(trashed), ["\(build).txt", "\(build).enabled", "\(build).meta.tsv", "\(build).values"])
        XCTAssertNil(store().state().file)
    }

    func testInstallTrashesAnOldMetaFile() throws {
        try store().install(abc, replacing: false)
        try Data("name\tsection\nA\tOld\n".utf8).write(to: folder.appendingPathComponent("\(build).meta.tsv"))
        try store().install(abc, replacing: true)
        XCTAssertEqual(trashed, ["\(build).meta.tsv"])
        XCTAssertNil(store().state().file?.entries.first?.section)
    }
}
