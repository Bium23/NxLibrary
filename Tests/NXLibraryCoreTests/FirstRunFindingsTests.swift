import XCTest
@testable import NXLibraryCore

final class FirstRunFindingsTests: XCTestCase {
    private func emptyApps() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FirstRunApps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testMissingSteamFolderCountsNothing() throws {
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent("NoSteam-\(UUID().uuidString)")
        let findings = FirstRunFindings.read(steamRoot: absent, appsFolder: try emptyApps(), cancelled: { false })
        XCTAssertNil(findings.steamGameCount)
        XCTAssertEqual(findings.portedAppCount, 0)
        XCTAssertTrue(findings.isEmpty)
    }

    func testOnlyNativeReadyGamesCount() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        try f.manifest(in: root)
        try f.app(at: "Steam/steamapps/common/First/Game.app")
        try f.manifest(in: root, id: "20", name: "Second game", directory: "Second")
        try f.app(at: "Steam/steamapps/common/Second/Game.app")
        try f.manifest(in: root, id: "30", name: "Downloading", directory: "Third", stateFlags: "1026")
        try f.manifest(in: root, id: "40", name: "Windows only", directory: "Fourth")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("steamapps/common/Fourth"),
                                                withIntermediateDirectories: true)
        let snapshot = try SteamLibrarySource(root: root).scan()
        XCTAssertTrue(snapshot.games.contains { $0.state == .downloading })
        XCTAssertTrue(snapshot.games.contains { $0.state != .nativeReady && $0.state != .downloading })
        XCTAssertTrue(snapshot.isComplete)

        let findings = FirstRunFindings.read(steamRoot: root, appsFolder: try emptyApps(), cancelled: { false })
        XCTAssertEqual(findings.steamGameCount, 2)
        XCTAssertFalse(findings.isEmpty)
    }

    func testSteamWithNoMacGamesCountsZero() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        let findings = FirstRunFindings.read(steamRoot: root, appsFolder: try emptyApps(), cancelled: { false })
        XCTAssertEqual(findings.steamGameCount, 0)
    }

    func testUnreadableOrPartialSteamCountsNothing() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        try f.manifest(in: root)
        try f.app(at: "Steam/steamapps/common/First/Game.app")
        let broken = try f.manifest(in: root, id: "20", name: "Broken", directory: "Second")
        try Data("AppState {".utf8).write(to: broken)
        XCTAssertNil(FirstRunFindings.read(steamRoot: root, appsFolder: try emptyApps(), cancelled: { false }).steamGameCount)

        let unreadable = try f.library("Locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unreadable.path) }
        XCTAssertNil(FirstRunFindings.read(steamRoot: unreadable, appsFolder: try emptyApps(), cancelled: { false }).steamGameCount)
    }

    func testCancelledReadStops() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        try f.manifest(in: root)
        try f.app(at: "Steam/steamapps/common/First/Game.app")
        let findings = FirstRunFindings.read(steamRoot: root, appsFolder: try emptyApps(), cancelled: { true })
        XCTAssertEqual(findings, FirstRunFindings(steamGameCount: nil, portedAppCount: 0))
    }

    func testPortedAppsAreCounted() throws {
        let apps = try emptyApps()
        let contents = apps.appendingPathComponent("Zelda.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "Ported", "CFBundleIdentifier": "org.nxnative.01007ef00011e000",
            "CFBundleShortVersionString": "1.0", "DMTitleID": "01007EF00011E000",
        ], format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent("NoSteam-\(UUID().uuidString)")
        let findings = FirstRunFindings.read(steamRoot: absent, appsFolder: apps, cancelled: { false })
        XCTAssertEqual(findings.portedAppCount, 1)
        XCTAssertFalse(findings.isEmpty)
    }
}
