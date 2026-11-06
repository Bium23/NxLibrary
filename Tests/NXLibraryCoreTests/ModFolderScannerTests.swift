import XCTest
@testable import NXLibraryCore

final class ModFolderScannerTests: XCTestCase {
    private var dir: URL!
    private let tid = "0100000000010000"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ModScanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func file(_ path: String) throws {
        let url = dir.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic".utf8).write(to: url)
    }

    func testPlainRomFSFolder() throws {
        try file("Mod/romfs/Data/a.bin")
        let mod = dir.appendingPathComponent("Mod")
        XCTAssertEqual(ModFolderScanner.romfs(in: mod, titleID: tid)?.standardizedFileURL,
                       mod.appendingPathComponent("romfs").standardizedFileURL)
    }

    func testAtmosphereLayoutResolvesInnerRomFS() throws {
        try file("A/atmosphere/contents/\(tid)/romfs/x.bin")
        try file("B/contents/\(tid.lowercased())/romfs/y.bin")
        let a = dir.appendingPathComponent("A"), b = dir.appendingPathComponent("B")
        XCTAssertEqual(ModFolderScanner.romfs(in: a, titleID: tid)?.standardizedFileURL,
                       a.appendingPathComponent("atmosphere/contents/\(tid)/romfs").standardizedFileURL)
        XCTAssertEqual(ModFolderScanner.romfs(in: b, titleID: tid)?.standardizedFileURL,
                       b.appendingPathComponent("contents/\(tid.lowercased())/romfs").standardizedFileURL)
    }

    func testFolderWithoutRomFSIsListedButCannotBeOn() throws {
        try file("Loose/Data/a.bin")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Empty"), withIntermediateDirectories: true)
        XCTAssertNil(ModFolderScanner.romfs(in: dir.appendingPathComponent("Loose"), titleID: tid))
        XCTAssertNil(ModFolderScanner.romfs(in: dir.appendingPathComponent("Empty"), titleID: tid))
        XCTAssertEqual(ModFolderScanner.entries(in: dir).map(\.lastPathComponent), ["Empty", "Loose"])
    }

    func testSymlinkedRomFSIsRejected() throws {
        try file("Elsewhere/x.bin")
        let mod = dir.appendingPathComponent("Linked")
        try FileManager.default.createDirectory(at: mod, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: mod.appendingPathComponent("romfs"),
                                                   withDestinationURL: dir.appendingPathComponent("Elsewhere"))
        XCTAssertNil(ModFolderScanner.romfs(in: mod, titleID: tid))
    }

    func testEntriesAreSortedSkipHiddenAndKeepStrayFiles() throws {
        try file(".DS_Store")
        try file("mod.zip")
        try file("b/romfs/x")
        try file("a/romfs/x")
        try file(".hidden/romfs/x")
        // A stray file (an archive not unzipped yet) is listed, so the panel can say it is not a mod.
        XCTAssertEqual(ModFolderScanner.entries(in: dir).map(\.lastPathComponent), ["a", "b", "mod.zip"])
        XCTAssertEqual(ModFolderScanner.entries(in: dir.appendingPathComponent("missing")), [])
    }

    func testFilesAreRelativePaths() throws {
        try file("Mod/romfs/Data/x.bin")
        try file("Mod/romfs/Top.txt")
        let romfs = dir.appendingPathComponent("Mod/romfs")
        XCTAssertEqual(ModFolderScanner.files(under: romfs), ["Data/x.bin", "Top.txt"])
    }

    func testFilesSkipHiddenFinderFiles() throws {
        try file("Mod/romfs/.DS_Store")
        try file("Mod/romfs/Data/.DS_Store")
        try file("Mod/romfs/Data/x.bin")
        XCTAssertEqual(ModFolderScanner.files(under: dir.appendingPathComponent("Mod/romfs")), ["Data/x.bin"])
    }
}
