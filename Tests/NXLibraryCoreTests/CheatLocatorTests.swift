import XCTest
@testable import NXLibraryCore

final class CheatLocatorTests: XCTestCase {
    private var dir: URL!
    private var home: URL!
    private var app: URL!
    private let tid = "0100000000010000"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("CheatLocator-\(UUID().uuidString)")
        home = dir.appendingPathComponent("home")
        app = dir.appendingPathComponent("Game.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Resources/dm"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private var support: URL { home.appendingPathComponent("Library/Application Support/nxnative/\(tid)") }

    private func write(_ text: String, _ url: URL) throws { try Data(text.utf8).write(to: url) }

    private func writePlist(_ info: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
    }

    func testBuildIDFromFixupsHeader() throws {
        let fixups = app.appendingPathComponent("Contents/Resources/dm/main.fixups.tsv")
        try write("# PATCH_OFF\t0x1\n# BUILD_ID\tb424be150a8e7d78701cbe7a439d9ebf\n0x10\t1\n", fixups)
        XCTAssertEqual(CheatLocator.buildID(appURL: app), "B424BE150A8E7D78")
        try write("# PATCH_OFF\t0x1\n", fixups)
        XCTAssertNil(CheatLocator.buildID(appURL: app))
        try write("# BUILD_ID\tb424\n", fixups)
        XCTAssertNil(CheatLocator.buildID(appURL: app))
        try write("# BUILD_ID\tzz24be150a8e7d78\n", fixups)
        XCTAssertNil(CheatLocator.buildID(appURL: app), "not hex")
        try FileManager.default.removeItem(at: fixups)
        XCTAssertNil(CheatLocator.buildID(appURL: app))
    }

    /// hle_cheats.c names the flag files with the program ID upper case (%016llX).
    func testTitleIDPrefersInfoPlist() throws {
        try writePlist(["DMTitleID": "0100f2c0115b6000"])
        XCTAssertEqual(CheatLocator.titleID(appURL: app, fallback: "X"), "0100F2C0115B6000")
        try writePlist(["CFBundleName": "Game"])
        XCTAssertEqual(CheatLocator.titleID(appURL: app, fallback: "0100000000010000"), "0100000000010000")
        XCTAssertNil(CheatLocator.titleID(appURL: app, fallback: nil))
        try writePlist(["DMTitleID": "a/b"])
        XCTAssertNil(CheatLocator.titleID(appURL: app, fallback: nil))
    }

    func testFolderDefault() {
        XCTAssertEqual(CheatLocator.folder(titleID: tid, appURL: app, home: home)?.path,
                       support.appendingPathComponent("cheats").path)
    }

    func testMalformedProgramIDsCannotEscapeTheGamesDataFolder() throws {
        for invalid in ["..", ".", "not-a-title", "010000000001000", "０１０００００００００１００００"] {
            try writePlist(["DMTitleID": invalid])
            XCTAssertNil(CheatLocator.titleID(appURL: app, fallback: tid),
                         "\(invalid): an invalid declared identity must not use a different game's fallback")
            XCTAssertNil(CheatLocator.folder(titleID: invalid, appURL: app, home: home), invalid)
        }
        try writePlist(["CFBundleName": "Game"])
        XCTAssertNil(CheatLocator.titleID(appURL: app, fallback: ".."))
    }

    /// Review Focus 3: dm/mac/launcher.c env_file, the data folder's env.txt first, then the app's; the first value of a
    /// key wins; DM_CHEATS before DM_ROOT (hle_cheats.c dm_cheats_init); an empty value counts as unset there.
    func testFolderFollowsEnvFilesInLauncherOrder() throws {
        let supportEnv = support.appendingPathComponent("env.txt")
        let appEnv = app.appendingPathComponent("Contents/Resources/dm/env.txt")
        try write("# moved\n\n  DM_ROOT = /Volumes/My Games/smo\r\nDM_ROOT=/later\n", supportEnv)
        try write("DM_CHEATS=/x\n", appEnv)
        XCTAssertEqual(CheatLocator.folder(titleID: tid, appURL: app, home: home)?.path, "/x",
                       "DM_CHEATS from the app's file beats DM_ROOT from the data folder's")
        try write("DM_ROOT=/Volumes/My Games/smo\nDM_ROOT=/later\n", supportEnv)
        try write("", appEnv)
        XCTAssertEqual(CheatLocator.folder(titleID: tid, appURL: app, home: home)?.path, "/Volumes/My Games/smo/cheats")
        try write("DM_CHEATS=/y\n", supportEnv)
        try write("DM_CHEATS=/x\n", appEnv)
        XCTAssertEqual(CheatLocator.folder(titleID: tid, appURL: app, home: home)?.path, "/y")
        try FileManager.default.removeItem(at: supportEnv)
        try write("DM_ROOT=/z\n", appEnv)
        XCTAssertEqual(CheatLocator.folder(titleID: tid, appURL: app, home: home)?.path, "/z/cheats")
        try write("DM_CHEATS=\nDM_ROOT=\n", appEnv)
        XCTAssertNil(CheatLocator.folder(titleID: tid, appURL: app, home: home), "an empty DM_ROOT leaves the host without a folder")
    }
}
