import XCTest
@testable import NXLibraryCore

final class EnvFileEditorTests: XCTestCase {
    private var dir: URL!
    private var env: URL { dir.appendingPathComponent("TID/env.txt") }
    private let key = "DM_ROMFS_OVERLAY"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("EnvEditor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: env.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: env, atomically: true, encoding: .utf8)
    }

    private func read() -> String? { try? String(contentsOf: env, encoding: .utf8) }

    func testAppendsWhenMissing() throws {
        try EnvFileEditor.set(key, to: "/a/romfs", in: env)
        XCTAssertEqual(read(), "DM_ROMFS_OVERLAY=/a/romfs\n")
        try write("DM_FPS_TARGET=60")
        try EnvFileEditor.set(key, to: "/b/romfs", in: env)
        XCTAssertEqual(read(), "DM_FPS_TARGET=60\nDM_ROMFS_OVERLAY=/b/romfs\n")
    }

    func testReplacesInPlaceKeepingOtherLinesAndComments() throws {
        try write("# mine\nDM_FPS_TARGET=60\nDM_ROMFS_OVERLAY=/old\nDM_X=1\n")
        try EnvFileEditor.set(key, to: "/new/romfs:/b c/romfs", in: env)
        XCTAssertEqual(read(), "# mine\nDM_FPS_TARGET=60\nDM_ROMFS_OVERLAY=/new/romfs:/b c/romfs\nDM_X=1\n")
    }

    func testRemovesKeyAndDuplicates() throws {
        try write("DM_ROMFS_OVERLAY=/one\nDM_X=1\n  DM_ROMFS_OVERLAY = /two\n")
        try EnvFileEditor.set(key, to: nil, in: env)
        XCTAssertEqual(read(), "DM_X=1\n")
        try write("DM_ROMFS_OVERLAY=/one\nDM_X=1\nDM_ROMFS_OVERLAY=/two\n")
        try EnvFileEditor.set(key, to: "/three", in: env)
        XCTAssertEqual(read(), "DM_ROMFS_OVERLAY=/three\nDM_X=1\n")
    }

    func testCommentedKeyIsNotTouched() throws {
        try write("# DM_ROMFS_OVERLAY=/kept\nDM_X=1\n")
        try EnvFileEditor.set(key, to: "/a", in: env)
        XCTAssertEqual(read(), "# DM_ROMFS_OVERLAY=/kept\nDM_X=1\nDM_ROMFS_OVERLAY=/a\n")
    }

    func testCRLFInputIsPreserved() throws {
        try write("DM_X=1\r\nDM_ROMFS_OVERLAY=/old\r\n")
        try EnvFileEditor.set(key, to: "/new", in: env)
        XCTAssertEqual(read(), "DM_X=1\r\nDM_ROMFS_OVERLAY=/new\r\n")
    }

    func testRemovingFromMissingFileCreatesNothing() throws {
        try EnvFileEditor.set(key, to: nil, in: env)
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.deletingLastPathComponent().path))
    }

    func testLaunchMergeKeepsOverlay() {
        let merged = GameRuntimeConfig().mergedEnvContent(existing: "DM_ROMFS_OVERLAY=/a/romfs:/b c/romfs\n")
        XCTAssertTrue(merged.components(separatedBy: "\n").contains("DM_ROMFS_OVERLAY=/a/romfs:/b c/romfs"))
    }
}
