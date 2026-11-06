import XCTest
@testable import NXLibraryCore

final class ModStoreTests: XCTestCase {
    private var dir: URL!
    private let tid = "0100000000010000"
    private var support: URL { dir.appendingPathComponent("nxnative/\(tid)") }
    private var mods: URL { support.appendingPathComponent("mods") }
    private var env: URL { support.appendingPathComponent("env.txt") }
    private var records: URL { dir.appendingPathComponent("NXLibrary/mods/\(tid).json") }
    private var allowed = true
    private var trashed: [String] = []

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ModStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        allowed = true
        trashed = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func store() -> ModStore {
        ModStore(supportFolder: support, recordsFile: records, titleID: tid,
                 canWrite: { [unowned self] in allowed },
                 trash: { [unowned self] url in trashed.append(url.lastPathComponent); try FileManager.default.removeItem(at: url) })
    }

    @discardableResult
    private func mod(_ name: String, files: [String] = ["Data/a.bin"]) throws -> URL {
        let folder = mods.appendingPathComponent(name)
        for file in files {
            let url = folder.appendingPathComponent("romfs").appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("synthetic".utf8).write(to: url)
        }
        return folder
    }

    private func romfs(_ name: String) -> String { mods.appendingPathComponent(name).appendingPathComponent("romfs").path }
    private func envText() -> String? { try? String(contentsOf: env, encoding: .utf8) }

    func testHandInstalledModsAppearOffAtTheBottom() throws {
        try mod("Zeta"); try mod("Alpha"); try mod("Beta")
        try store().setOn(true, folderName: "Zeta")
        try mod("Gamma")
        let list = store().mods()
        // The first change records the folders where they stand (by name); Gamma came later: off, at the bottom.
        XCTAssertEqual(list.map(\.folderName), ["Alpha", "Beta", "Zeta", "Gamma"])
        XCTAssertEqual(list.map(\.isOn), [false, false, true, false])
    }

    func testTurningOnWritesOverlayTopFirst() throws {
        try mod("A"); try mod("B")
        try store().setOn(true, folderName: "A")
        try store().setOn(true, folderName: "B")
        XCTAssertEqual(envText(), "DM_ROMFS_OVERLAY=\(romfs("A")):\(romfs("B"))\n")
        XCTAssertEqual(store().overlayValue(), "\(romfs("A")):\(romfs("B"))")
    }

    func testTurningAllOffRemovesTheLine() throws {
        try mod("A")
        try "DM_X=1\n".write(to: { try! FileManager.default.createDirectory(at: support, withIntermediateDirectories: true); return env }(),
                              atomically: true, encoding: .utf8)
        try store().setOn(true, folderName: "A")
        try store().setOn(false, folderName: "A")
        XCTAssertEqual(envText(), "DM_X=1\n")
        XCTAssertNil(store().overlayValue())
    }

    func testMoveChangesOverlayOrder() throws {
        try mod("A"); try mod("B")
        try store().setOn(true, folderName: "A")
        try store().setOn(true, folderName: "B")
        try store().move(folderName: "B", by: -1)
        XCTAssertEqual(store().mods().map(\.folderName), ["B", "A"])
        XCTAssertEqual(envText(), "DM_ROMFS_OVERLAY=\(romfs("B")):\(romfs("A"))\n")
        try store().move(folderName: "B", by: -5)
        XCTAssertEqual(store().mods().map(\.folderName), ["B", "A"], "moving past the top stays at the top")
    }

    func testRemoveTrashesFolderAndRecord() throws {
        try mod("A"); try mod("B")
        try store().setOn(true, folderName: "A")
        try store().setOn(true, folderName: "B")
        try store().remove(folderName: "A")
        XCTAssertEqual(trashed, ["A"])
        XCTAssertEqual(store().mods().map(\.folderName), ["B"])
        XCTAssertEqual(envText(), "DM_ROMFS_OVERLAY=\(romfs("B"))\n")
    }

    func testNotAllowedWhileRunning() throws {
        try mod("A")
        allowed = false
        XCTAssertThrowsError(try store().setOn(true, folderName: "A")) { XCTAssertEqual($0 as? ModStoreError, .notAllowed) }
        XCTAssertThrowsError(try store().move(folderName: "A", by: 1)) { XCTAssertEqual($0 as? ModStoreError, .notAllowed) }
        XCTAssertThrowsError(try store().remove(folderName: "A")) { XCTAssertEqual($0 as? ModStoreError, .notAllowed) }
        XCTAssertNil(envText())
        XCTAssertFalse(FileManager.default.fileExists(atPath: records.path))
        XCTAssertEqual(trashed, [])
    }

    func testFolderWithoutRomFSCannotBeTurnedOn() throws {
        try FileManager.default.createDirectory(at: mods.appendingPathComponent("Loose/Data"), withIntermediateDirectories: true)
        let list = store().mods()
        XCTAssertEqual(list.map(\.folderName), ["Loose"])
        XCTAssertNil(list[0].romfs)
        XCTAssertThrowsError(try store().setOn(true, folderName: "Loose")) { XCTAssertEqual($0 as? ModStoreError, .notAMod("Loose")) }
        XCTAssertNil(envText())
    }

    func testColonInFolderNameCannotBeOn() throws {
        try mod("Zelda: HD")
        XCTAssertThrowsError(try store().setOn(true, folderName: "Zelda: HD")) {
            XCTAssertEqual($0 as? ModStoreError, .colonInName("Zelda: HD"))
        }
        XCTAssertNil(envText())
    }

    func testOverlayOverLimitIsRefused() throws {
        let long = String(repeating: "x", count: 200)
        var names: [String] = []
        for i in 0..<30 { names.append("\(i)-\(long)"); try mod(names[i]) }
        var refused: String?
        for name in names {
            do { try store().setOn(true, folderName: name) } catch ModStoreError.overlayTooLong { refused = name; break }
        }
        XCTAssertNotNil(refused)
        let value = try XCTUnwrap(store().overlayValue())
        XCTAssertLessThanOrEqual(value.utf8.count, ModStore.overlayLimit)
        XCTAssertEqual(envText(), "DM_ROMFS_OVERLAY=\(value)\n")
        XCTAssertFalse(store().mods().first { $0.folderName == refused }!.isOn)
    }

    func testConflictWhenTwoOnModsShareAFile() throws {
        try mod("A", files: ["Data/x.bin", "Data/a.bin"])
        try mod("B", files: ["Data/x.bin", "Data/b.bin"])
        try mod("C", files: ["Data/x.bin"])
        try store().setOn(true, folderName: "A")
        try store().setOn(true, folderName: "B")
        let conflicts = store().conflicts()
        XCTAssertEqual(conflicts, [ModConflict(upper: "A", lower: "B")])
        XCTAssertEqual(conflicts.first?.message, "A and B change the same files: the upper one wins.")
    }

    func testMissingFolderIsDroppedAndOverlayRewritten() throws {
        let a = try mod("A"); try mod("B")
        try store().setOn(true, folderName: "A")
        try store().setOn(true, folderName: "B")
        try FileManager.default.removeItem(at: a)
        try store().sync()
        XCTAssertEqual(store().mods().map(\.folderName), ["B"])
        XCTAssertEqual(envText(), "DM_ROMFS_OVERLAY=\(romfs("B"))\n")
        let saved = try JSONDecoder().decode([ModRecord].self, from: Data(contentsOf: records))
        XCTAssertEqual(saved.map(\.folderName), ["B"])
    }

    func testSyncDoesNothingWhileRunning() throws {
        let a = try mod("A")
        try store().setOn(true, folderName: "A")
        try FileManager.default.removeItem(at: a)
        allowed = false
        try store().sync()
        XCTAssertEqual(envText(), "DM_ROMFS_OVERLAY=\(romfs("A"))\n")
    }

    func testPlayerLinesInEnvAreKept() throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try "# mine\nDM_FPS_TARGET=30\n".write(to: env, atomically: true, encoding: .utf8)
        try mod("A")
        try store().setOn(true, folderName: "A")
        XCTAssertEqual(envText(), "# mine\nDM_FPS_TARGET=30\nDM_ROMFS_OVERLAY=\(romfs("A"))\n")
    }

    func testHiddenFinderFilesAreNotConflicts() throws {
        try mod("A", files: ["Data/a.bin", ".DS_Store"])
        try mod("B", files: ["Data/b.bin", ".DS_Store"])
        try store().setOn(true, folderName: "A")
        try store().setOn(true, folderName: "B")
        XCTAssertEqual(store().conflicts(), [])
    }

    func testStrayFileIsListedAsNotAModAndCanBeRemoved() throws {
        try mod("A")
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        try Data("zip".utf8).write(to: mods.appendingPathComponent("mod.zip"))
        let list = store().mods()
        XCTAssertEqual(list.map(\.folderName), ["A", "mod.zip"])
        XCTAssertNil(list[1].romfs)
        XCTAssertThrowsError(try store().setOn(true, folderName: "mod.zip")) { XCTAssertEqual($0 as? ModStoreError, .notAMod("mod.zip")) }
        try store().remove(folderName: "mod.zip")
        XCTAssertEqual(trashed, ["mod.zip"])
    }

    func testSyncOverLimitLeavesEnvAsIsAndSaysSo() throws {
        // The records say 20 long-named mods are on (for example after the player restructured them in Finder):
        // together they no longer fit the launcher's line.
        let names = (0..<20).map { "\($0)-" + String(repeating: "x", count: 200) }
        for name in names { try mod(name) }
        try FileManager.default.createDirectory(at: records.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(names.map { ModRecord(folderName: $0, isOn: true) }).write(to: records)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try "DM_X=1\n".write(to: env, atomically: true, encoding: .utf8)
        XCTAssertGreaterThan(try XCTUnwrap(store().overlayValue()).utf8.count, ModStore.overlayLimit)
        XCTAssertThrowsError(try store().sync()) { XCTAssertEqual($0 as? ModStoreError, .overlayTooLong) }
        XCTAssertTrue(envText() == "DM_X=1\n", "env.txt is left as it was")
    }

    func testSyncLeavesAHandWrittenOverlayWhenNXLibraryNeverManagedTheMods() throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try "DM_ROMFS_OVERLAY=/Users/me/my-mod\n".write(to: env, atomically: true, encoding: .utf8)
        try store().sync()
        XCTAssertEqual(envText(), "DM_ROMFS_OVERLAY=/Users/me/my-mod\n")
    }

    private func staged(_ text: String) throws -> URL {
        let romfs = mods.appendingPathComponent(".installing-\(UUID().uuidString)/romfs")
        try FileManager.default.createDirectory(at: romfs.appendingPathComponent("Data"), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: romfs.appendingPathComponent("Data/a.bin"))
        return romfs
    }

    func testAdoptUpdateKeepsPlaceAndState() throws {
        try mod("A"); try mod("C")
        XCTAssertTrue(try store().adopt(staged: staged("old"), folderName: "B",
                                        record: ModRecord(folderName: "B", isOn: false, gameBananaModID: 7), turnOn: true))
        // The first change records the folders where they stand (by name): B sits between A and C.
        XCTAssertEqual(store().mods().map(\.folderName), ["A", "B", "C"])
        let on = try store().adopt(staged: staged("new"), folderName: "ignored",
                                   record: ModRecord(folderName: "ignored", isOn: false, gameBananaModID: 7, gameBananaFileID: 2),
                                   turnOn: true)
        XCTAssertTrue(on)
        XCTAssertEqual(store().mods().map(\.folderName), ["A", "B", "C"])
        XCTAssertEqual(store().mods().map(\.isOn), [false, true, false])
        XCTAssertEqual(trashed, ["B"])
        XCTAssertEqual(try String(contentsOf: mods.appendingPathComponent("B/romfs/Data/a.bin"), encoding: .utf8), "new")
        XCTAssertEqual(store().gameBananaRecords()[7]?.gameBananaFileID, 2)
    }

    func testAdoptOverLimitInstallsOff() throws {
        let long = String(repeating: "x", count: 200)
        for i in 0..<30 {
            let name = "\(i)-\(long)"
            try mod(name)
            do { try store().setOn(true, folderName: name) } catch ModStoreError.overlayTooLong { break }
        }
        let before = envText()
        let on = try store().adopt(staged: staged("x"), folderName: "New \(long)",
                                   record: ModRecord(folderName: "New \(long)", isOn: false, gameBananaModID: 9), turnOn: true)
        XCTAssertFalse(on)
        XCTAssertEqual(store().mods().last?.folderName, "New \(long)")
        XCTAssertEqual(store().mods().last?.isOn, false)
        XCTAssertTrue(envText() == before)
    }

    func testAdoptRefusedWhileRunning() throws {
        let romfs = try staged("x")
        allowed = false
        XCTAssertThrowsError(try store().adopt(staged: romfs, folderName: "B",
                                               record: ModRecord(folderName: "B", isOn: false), turnOn: true)) {
            XCTAssertEqual($0 as? ModStoreError, .notAllowed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: mods.appendingPathComponent("B").path))
    }
}
