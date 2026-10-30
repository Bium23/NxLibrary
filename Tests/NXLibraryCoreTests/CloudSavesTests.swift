import XCTest
@testable import NXLibraryCore

final class CloudSavesTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSavesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testFolderURLs() {
        XCTAssertNil(CloudSaves.off.folderURL(home: home))
        XCTAssertEqual(CloudSaves.iCloudDrive.folderURL(home: home)?.path,
                       home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/nxnative Saves").path)
        XCTAssertEqual(CloudSaves.folder("/tmp/Saves").folderURL(home: home)?.path, "/tmp/Saves")
        XCTAssertNil(CloudSaves.folder("").folderURL(home: home))
    }

    func testSteppingSkipsFolderUntilOneIsPicked() {
        XCTAssertEqual(CloudSaves.off.stepped(1, picked: ""), .iCloudDrive)
        XCTAssertEqual(CloudSaves.iCloudDrive.stepped(1, picked: ""), .off)
        XCTAssertEqual(CloudSaves.iCloudDrive.stepped(1, picked: "/a"), .folder("/a"))
        XCTAssertEqual(CloudSaves.off.stepped(-1, picked: "/a"), .folder("/a"))
        XCTAssertEqual(CloudSaves.folder("/a").stepped(1, picked: "/a"), .off)
    }

    func testSettingsDecodeWithoutCloudSavesAsOff() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.cloudSaves, .off)
        XCTAssertEqual(decoded.cloudSavesPickedFolder, "")

        var settings = AppSettings()
        settings.cloudSaves = .folder("/x")
        settings.cloudSavesPickedFolder = "/x"
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(round.cloudSaves, .folder("/x"))
        XCTAssertEqual(round.cloudSavesPickedFolder, "/x")
    }

    func testApplyWritesEveryDomainOnceAndOffRemoves() throws {
        var writes: [String: String?] = [:]
        let prefs = CloudSavesPreferences(write: { writes[$1] = $0 }, home: home)
        let folder = home.appendingPathComponent("Saves")

        try prefs.apply(.folder(folder.path), to: ["org.nxnative.a", "org.nxnative.b", "org.nxnative.a"])
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes["org.nxnative.a"], .some(folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))

        try prefs.apply(.off, to: ["org.nxnative.a"])
        XCTAssertEqual(writes["org.nxnative.a"], .some(nil))
    }

    func testICloudDriveNeedsItsRoot() throws {
        var writes = 0
        let prefs = CloudSavesPreferences(write: { _, _ in writes += 1 }, home: home)
        XCTAssertThrowsError(try prefs.apply(.iCloudDrive, to: ["org.nxnative.a"])) {
            XCTAssertEqual($0 as? CloudSavesPreferences.Failure, .iCloudDriveOff)
        }
        XCTAssertEqual(writes, 0)

        try FileManager.default.createDirectory(at: CloudSaves.iCloudDriveRoot(home: home),
                                                withIntermediateDirectories: true)
        try prefs.apply(.iCloudDrive, to: ["org.nxnative.a"])
        XCTAssertEqual(writes, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: CloudSaves.iCloudDrive.folderURL(home: home)!.path))
    }

    func testOffBeforeLaunchLeavesTheGamesOwnChoice() throws {
        var writes = 0
        let prefs = CloudSavesPreferences(write: { _, _ in writes += 1 }, home: home)
        try prefs.applyBeforeLaunch(.off, domain: "org.nxnative.a")
        XCTAssertEqual(writes, 0)
    }
}
