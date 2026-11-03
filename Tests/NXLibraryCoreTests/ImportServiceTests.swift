import XCTest
@testable import NXLibraryCore

final class ImportServiceTests: XCTestCase {
    func testDuplicateTitleKeepsTheInstalledPathAndItsOwnMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = root.appendingPathComponent("Installed.app")
        let newURL = root.appendingPathComponent("Backup.app")
        for app in [oldURL, newURL] {
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        }
        let old = ImportedApp(name: "Installed", version: "1.0", titleId: "01007EF00011E000",
            bundleId: "org.nxnative.old", appURL: oldURL, sizeBytes: 100,
            modificationDate: Date(timeIntervalSince1970: 1))
        let newer = ImportedApp(name: "Backup", version: "2.0", titleId: old.titleId,
            bundleId: "org.nxnative.new", appURL: newURL, sizeBytes: 200,
            modificationDate: Date(timeIntervalSince1970: 2))
        let service = ImportService()
        let store = LibraryStore(directory: root.appendingPathComponent("Catalog"))
        _ = try store.merge(scanned: [service.makeGame(from: old)])
        let selected = service.appsForLibrary(scanned: [newer, old], existing: try store.load().games)
        XCTAssertEqual(selected.count, 1)
        let library = try store.merge(scanned: selected.map { service.makeGame(from: $0) })
        let game = try XCTUnwrap(library.games.first)
        XCTAssertEqual(game.url, oldURL)
        XCTAssertEqual(game.name, "Installed")
        XCTAssertEqual(game.versionString, "1.0")
        XCTAssertEqual(game.modificationDate, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(selected.first?.sizeBytes, 100)
        // A different chosen folder does not silently switch an existing installed app.
        XCTAssertTrue(service.appsForLibrary(scanned: [newer], existing: library.games).isEmpty)
        // If the old app is actually removed, the discovered build can replace its reference.
        try FileManager.default.removeItem(at: oldURL)
        XCTAssertEqual(service.appsForLibrary(scanned: [newer], existing: library.games).first?.appURL, newURL)
        // A new title with multiple builds starts with the newest scan result, once.
        XCTAssertEqual(service.appsForLibrary(scanned: [newer, old], existing: []).count, 1)
    }

    func testFindsNestedAppsWithoutEnteringBundlesOrFollowingDirectoryLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let game = root.appendingPathComponent("Games/Platform/Title/Game.app/Contents")
        let hidden = root.appendingPathComponent("Games/Other.app/Contents/Hidden.app/Contents")
        let outside = root.appendingPathComponent("Outside/External.app/Contents")
        for folder in [game, hidden, outside] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try nxnativePlist().write(to: folder.appendingPathComponent("Info.plist"))
        }
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("Games/Loop").path,
                                                   withDestinationPath: root.appendingPathComponent("Games").path)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("Games/External").path,
                                                   withDestinationPath: root.appendingPathComponent("Outside").path)
        let apps = ImportService().scan(directories: [root.appendingPathComponent("Games")])
        XCTAssertEqual(apps.map { $0.appURL.lastPathComponent }, ["Game.app"])
    }

    func testOverlappingRootsDoNotDuplicateTheSameApp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Game.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try nxnativePlist().write(to: contents.appendingPathComponent("Info.plist"))
        XCTAssertEqual(ImportService().scan(directories: [root, root]).count, 1)
    }

    func testDepthLimitReportsAnIncompleteScanAndPreservesShallowResults() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Direct.app", "Subfolder/Deep.app"] {
            let contents = root.appendingPathComponent(name + "/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try nxnativePlist().write(to: contents.appendingPathComponent("Info.plist"))
        }
        let service = ImportService(maximumDepth: 0)
        XCTAssertEqual(service.scan(directories: [root]).map { $0.appURL.lastPathComponent }, ["Direct.app"])
        XCTAssertFalse(service.scanWarnings.isEmpty)
    }

    func testDirectoryBudgetAndUnreadableRootAreReported() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Subfolder"), withIntermediateDirectories: true)
        let service = ImportService(maximumDirectories: 1)
        XCTAssertTrue(service.scan(directories: [root]).isEmpty)
        XCTAssertFalse(service.scanWarnings.isEmpty)
        XCTAssertTrue(service.scan(directories: [root.appendingPathComponent("Missing")]).isEmpty)
        XCTAssertFalse(service.scanWarnings.isEmpty)
    }

    func testFindsOnlyNxnativeApps() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXImport-\(UUID().uuidString)")
        let nxnative = root.appendingPathComponent("Zelda.app/Contents")
        let other = root.appendingPathComponent("Other.app/Contents")
        try FileManager.default.createDirectory(at: nxnative, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try nxnativePlist().write(to: nxnative.appendingPathComponent("Info.plist"))
        try otherPlist().write(to: other.appendingPathComponent("Info.plist"))
        let apps = ImportService().scan(directories: [root])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.titleId, "01007EF00011E000")
        XCTAssertEqual(apps.first?.name, "The Legend of Zelda: Breath of the Wild")

        let game = ImportService().makeGame(from: try XCTUnwrap(apps.first))
        XCTAssertEqual(game.status, .builtSourcesMissing)
        XCTAssertEqual(game.titleId, "01007EF00011E000")
        XCTAssertEqual(game.bundleId, "org.nxnative.01007ef00011e000")
        XCTAssertEqual(game.versionString, "1.9.0")
        XCTAssertEqual(game.url.lastPathComponent, "Zelda.app")
    }

    private func nxnativePlist() -> Data {
        try! PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "The Legend of Zelda: Breath of the Wild",
            "CFBundleIdentifier": "org.nxnative.01007ef00011e000",
            "CFBundleShortVersionString": "1.9.0",
            "DMTitleID": "01007EF00011E000",
        ], format: .xml, options: 0)
    }

    private func otherPlist() -> Data {
        try! PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "Other",
            "CFBundleIdentifier": "com.example.other",
        ], format: .xml, options: 0)
    }

    func testRejectsInvalidTitleIdsAndFallsBackToBundleSuffix() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXImportIDs-\(UUID().uuidString)")
        let bad = root.appendingPathComponent("Bad.app/Contents")
        let suffixOnly = root.appendingPathComponent("Suffix.app/Contents")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: suffixOnly, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "Bad",
            "CFBundleIdentifier": "org.nxnative.app",
            "DMTitleID": "../../../Documents/x",
        ], format: .xml, options: 0).write(to: bad.appendingPathComponent("Info.plist"))
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "Suffix",
            "CFBundleIdentifier": "org.nxnative.01007ef00011e000",
        ], format: .xml, options: 0).write(to: suffixOnly.appendingPathComponent("Info.plist"))

        let apps = ImportService().scan(directories: [root])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.titleId, "01007EF00011E000")
        try? FileManager.default.removeItem(at: root)
    }
}
