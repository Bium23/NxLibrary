import XCTest
import CryptoKit
@testable import NXLibraryCore

/// Runs bsdtar for real, except `-x` when told to fail, and can flip "game running" on `-x`.
private final class ScriptedRunner: CommandRunning {
    let real = SystemCommandRunner()
    var failExtract = false
    var onExtract: (() -> Void)?

    func run(_ executable: URL, _ arguments: [String], environment: [String: String]?,
             currentDirectory: URL?) throws -> CommandResult {
        if arguments.first == "-xf" {
            onExtract?()
            if failExtract { return CommandResult(status: 1, stdout: "", stderr: "truncated") }
        }
        return try real.run(executable, arguments, environment: environment, currentDirectory: currentDirectory)
    }
}

final class ModInstallerTests: XCTestCase {
    private var dir: URL!
    private let tid = "0100000000010000"
    private var allowed = true
    private var trashed: [String] = []
    private let runner = ScriptedRunner()
    private var space: Int64? = nil

    private var support: URL { dir.appendingPathComponent("nxnative/\(tid)") }
    private var mods: URL { support.appendingPathComponent("mods") }
    private var records: URL { dir.appendingPathComponent("NXLibrary/mods/\(tid).json") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ModInstaller-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func store() -> ModStore {
        ModStore(supportFolder: support, recordsFile: records, titleID: tid, canWrite: { [unowned self] in allowed },
                 trash: { [unowned self] url in trashed.append(url.lastPathComponent); try FileManager.default.removeItem(at: url) })
    }

    private func installer() -> ModInstaller {
        ModInstaller(store: store(), runner: runner, freeSpace: { [unowned self] _ in space },
                     now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }

    /// A zip of `files` (relative path → text), built with bsdtar from a source folder.
    private func archive(_ files: [String: String], name: String = "mod.zip") throws -> URL {
        let src = dir.appendingPathComponent("src-\(UUID().uuidString)")
        for (path, text) in files {
            let url = src.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let out = dir.appendingPathComponent(name)
        let result = try SystemCommandRunner().run(URL(fileURLWithPath: "/usr/bin/bsdtar"), ["-a", "-cf", out.path, "-C", src.path, "."],
                                                   environment: nil, currentDirectory: nil)
        XCTAssertEqual(result.status, 0, result.stderr)
        return out
    }

    private func file(for archive: URL, id: Int = 77) throws -> GameBananaFile {
        let data = try Data(contentsOf: archive)
        let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return GameBananaFile(id: id, name: archive.lastPathComponent, size: Int64(data.count),
                              downloadURL: URL(string: "https://gamebanana.com/dl/\(id)"), md5: md5)
    }

    private func mod(_ name: String = "Pack", id: Int = 49049) -> AvailableMod {
        AvailableMod(id: id, rank: 0, name: name, author: "A", avatarURL: nil, images: [], thumbnailURL: nil, version: "",
                     updated: Date(), pageURL: URL(string: "https://gamebanana.com/mods/\(id)")!, description: "",
                     likes: 0, downloads: 0, files: [])
    }

    private func newEntries() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: mods.path)) ?? []).sorted()
    }

    private func envText() -> String? { try? String(contentsOf: support.appendingPathComponent("env.txt"), encoding: .utf8) }

    private func assertInstallFails(_ expected: ModInstallError, archive: URL, gbFile: GameBananaFile? = nil,
                                    line: UInt = #line) throws {
        let gbFile = try gbFile ?? file(for: archive)
        XCTAssertThrowsError(try installer().install(archive: archive, file: gbFile, mod: mod()), line: line) {
            XCTAssertEqual($0 as? ModInstallError, expected, line: line)
        }
    }

    func testVerifyChecksSizeThenMD5() throws {
        let zip = try archive(["romfs/a.bin": "x"])
        let good = try file(for: zip)
        XCTAssertNoThrow(try ModInstaller.verify(zip, file: good))
        let wrongSize = GameBananaFile(id: 1, name: "", size: good.size + 1, downloadURL: nil, md5: good.md5)
        XCTAssertThrowsError(try ModInstaller.verify(zip, file: wrongSize)) { XCTAssertEqual($0 as? ModInstallError, .damaged) }
        let wrongMD5 = GameBananaFile(id: 1, name: "", size: good.size, downloadURL: nil, md5: String(repeating: "0", count: 32))
        XCTAssertThrowsError(try ModInstaller.verify(zip, file: wrongMD5)) { XCTAssertEqual($0 as? ModInstallError, .damaged) }
        let upper = GameBananaFile(id: 1, name: "", size: good.size, downloadURL: nil, md5: good.md5.uppercased())
        XCTAssertNoThrow(try ModInstaller.verify(zip, file: upper))
    }

    func testInstallsPrefixedRomFSAndTurnsOn() throws {
        let zip = try archive(["Pack 1.4/romfs/Data/a.bin": "new", "Pack 1.4/readme.txt": "hi"])
        let gb = try file(for: zip)
        XCTAssertEqual(try installer().install(archive: zip, file: gb, mod: mod()), .on("Pack"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: mods.appendingPathComponent("Pack/romfs/Data/a.bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mods.appendingPathComponent("Pack/readme.txt").path))
        XCTAssertEqual(newEntries(), ["Pack"])
        let record = try XCTUnwrap(store().gameBananaRecords()[49049])
        XCTAssertEqual(record.gameBananaFileID, 77)
        XCTAssertEqual(record.md5, gb.md5)
        XCTAssertEqual(record.installedAt, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(record.isOn)
        XCTAssertEqual(envText(), "DM_ROMFS_OVERLAY=\(mods.appendingPathComponent("Pack/romfs").path)\n")
    }

    func testWriteFailureShowsAFixedSentence() {
        XCTAssertEqual(ModInstallError.writeFailed("The file \u{201C}a.bin\u{201D} couldn\u{2019}t be saved.").message,
                       "The mod couldn't be copied into the game's folder. Try again.")
    }

    func testSymlinkEntryIsRefusedBeforeUnpacking() throws {
        let outside = dir.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let src = dir.appendingPathComponent("src-link")
        try FileManager.default.createDirectory(at: src.appendingPathComponent("romfs/real"), withIntermediateDirectories: true)
        try Data("y".utf8).write(to: src.appendingPathComponent("romfs/real/x.bin"))
        try FileManager.default.createSymbolicLink(atPath: src.appendingPathComponent("romfs/link").path,
                                                   withDestinationPath: outside.path)
        let evil = dir.appendingPathComponent("link.tar")
        let tar = URL(fileURLWithPath: "/usr/bin/bsdtar")
        XCTAssertEqual(try SystemCommandRunner().run(tar, ["-cf", evil.path, "romfs/link"], environment: nil,
                                                     currentDirectory: src).status, 0)
        XCTAssertEqual(try SystemCommandRunner().run(tar, ["-rf", evil.path, "-s", ",romfs/real,romfs/link,", "romfs/real/x.bin"],
                                                     environment: nil, currentDirectory: src).status, 0)
        var extracted = false
        runner.onExtract = { extracted = true }
        try assertInstallFails(.unsafe, archive: evil)
        XCTAssertFalse(extracted)
        XCTAssertEqual(newEntries(), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    func testHardlinkEntryIsRefusedBeforeUnpacking() throws {
        let src = dir.appendingPathComponent("src-hard")
        try FileManager.default.createDirectory(at: src.appendingPathComponent("romfs"), withIntermediateDirectories: true)
        try Data("y".utf8).write(to: src.appendingPathComponent("romfs/a.bin"))
        try FileManager.default.linkItem(at: src.appendingPathComponent("romfs/a.bin"), to: src.appendingPathComponent("romfs/b.bin"))
        let evil = dir.appendingPathComponent("hard.tar")
        XCTAssertEqual(try SystemCommandRunner().run(URL(fileURLWithPath: "/usr/bin/bsdtar"), ["-cf", evil.path, "romfs"],
                                                     environment: nil, currentDirectory: src).status, 0)
        var extracted = false
        runner.onExtract = { extracted = true }
        try assertInstallFails(.unsafe, archive: evil)
        XCTAssertFalse(extracted)
        XCTAssertEqual(newEntries(), [])
    }

    func testTraversalArchiveIsUnsafe() throws {
        let payload = dir.appendingPathComponent("a.bin")
        try Data("y".utf8).write(to: payload)
        let evil = dir.appendingPathComponent("evil.tar")
        let result = try SystemCommandRunner().run(URL(fileURLWithPath: "/usr/bin/bsdtar"),
                                                   ["-P", "-cf", evil.path, "-s", ",^,../romfs/,", "a.bin"],
                                                   environment: nil, currentDirectory: dir)
        XCTAssertEqual(result.status, 0, result.stderr)
        try assertInstallFails(.unsafe, archive: evil)
        XCTAssertEqual(newEntries(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("romfs").path))
    }

    func testCodeModArchiveIsNoRomFS() throws {
        try assertInstallFails(.noRomFS, archive: try archive(["exefs/main.npdm": "code"]))
        XCTAssertEqual(newEntries(), [])
    }

    func testFailedExtractLeavesNothing() throws {
        runner.failExtract = true
        try assertInstallFails(.unreadable, archive: try archive(["romfs/a.bin": "x"]))
        XCTAssertEqual(newEntries(), [])
        XCTAssertTrue(store().gameBananaRecords().isEmpty)
        XCTAssertNil(envText())
    }

    func testGameStartedDuringInstallIsRefused() throws {
        runner.onExtract = { [unowned self] in allowed = false }
        try assertInstallFails(.notAllowed, archive: try archive(["romfs/a.bin": "x"]))
        XCTAssertEqual(newEntries(), [])
        XCTAssertNil(envText())
    }

    func testRefusedWhileRunningBeforeAnything() throws {
        allowed = false
        try assertInstallFails(.notAllowed, archive: try archive(["romfs/a.bin": "x"]))
    }

    func testNoSpace() throws {
        space = 10
        try assertInstallFails(.noSpace, archive: try archive(["romfs/a.bin": "x"]))
        XCTAssertEqual(newEntries(), [])
    }

    func testNameCollisionGetsSuffix() throws {
        try FileManager.default.createDirectory(at: mods.appendingPathComponent("Pack/romfs"), withIntermediateDirectories: true)
        let zip = try archive(["romfs/a.bin": "x"])
        XCTAssertEqual(try installer().install(archive: zip, file: try file(for: zip), mod: mod()), .on("Pack 2"))
        XCTAssertEqual(newEntries(), ["Pack", "Pack 2"])
    }

    func testUpdateKeepsFolderAndState() throws {
        let first = try archive(["romfs/a.bin": "old"], name: "one.zip")
        XCTAssertEqual(try installer().install(archive: first, file: try file(for: first, id: 1), mod: mod()), .on("Pack"))
        try store().setOn(false, folderName: "Pack")
        let second = try archive(["romfs/a.bin": "new"], name: "two.zip")
        XCTAssertEqual(try installer().install(archive: second, file: try file(for: second, id: 2), mod: mod()), .off("Pack"))
        XCTAssertEqual(try String(contentsOf: mods.appendingPathComponent("Pack/romfs/a.bin"), encoding: .utf8), "new")
        XCTAssertEqual(store().gameBananaRecords()[49049]?.gameBananaFileID, 2)
        XCTAssertEqual(trashed, ["Pack"])
    }
}
