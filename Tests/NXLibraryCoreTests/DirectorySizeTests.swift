import XCTest
@testable import NXLibraryCore

final class DirectorySizeTests: XCTestCase {
    func testCountsRegularFilesAndSkipsHiddenEntriesAndLinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let nested = root.appendingPathComponent("Game.app/Contents/Resources")
        let hiddenFolder = root.appendingPathComponent("Game.app/.cache")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try fm.createDirectory(at: hiddenFolder, withIntermediateDirectories: true)
        try Data(count: 1000).write(to: nested.appendingPathComponent("romfs.img"))
        try Data(count: 24).write(to: root.appendingPathComponent("Game.app/Contents/Info.plist"))
        try Data(count: 500).write(to: nested.appendingPathComponent(".DS_Store"))
        try Data(count: 700).write(to: hiddenFolder.appendingPathComponent("visible-inside-hidden"))
        try fm.createSymbolicLink(at: nested.appendingPathComponent("link"),
                                  withDestinationURL: nested.appendingPathComponent("romfs.img"))

        XCTAssertEqual(DirectorySize.bytes(at: root.appendingPathComponent("Game.app")), 1024)
    }

    func testMissingFolderIsZero() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(DirectorySize.bytes(at: missing), 0)
    }
}
