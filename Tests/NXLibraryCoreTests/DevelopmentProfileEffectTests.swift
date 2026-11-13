import XCTest
@testable import NXLibraryCore

final class DevelopmentProfileEffectTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NXEffects-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testAutomaticModSyncCannotOverwriteRealOverlayFromCopiedRecords() throws {
        let root = try root()
        let game = root.appendingPathComponent("real-game")
        try FileManager.default.createDirectory(at: game.appendingPathComponent("mods/Foo/romfs"), withIntermediateDirectories: true)
        let env = game.appendingPathComponent("env.txt")
        let original = "DM_ROMFS_OVERLAY=/current-stable-choice\n"
        try Data(original.utf8).write(to: env)
        let records = root.appendingPathComponent("development-records.json")
        try JSONEncoder().encode([ModRecord(folderName: "Foo", isOn: true)]).write(to: records)
        let store = ModStore(supportFolder: game, recordsFile: records, titleID: "0100000000000000", canWrite: { true }, trash: { _ in XCTFail() }, allowsAutomaticMaintenance: false)
        try store.sync()
        XCTAssertEqual(try String(contentsOf: env), original)
        try store.sync(automatic: false)
        XCTAssertNotEqual(try String(contentsOf: env), original, "Explicit changes must remain possible")
    }
    func testBrowsingUsesActualOverlayAndKeepsOtherProfilesInstallStaging() throws {
        let root = try root()
        let game = root.appendingPathComponent("game")
        for name in ["Foo", "Bar", ".installing-other-profile"] {
            try FileManager.default.createDirectory(at: game.appendingPathComponent("mods/" + name + "/romfs"), withIntermediateDirectories: true)
        }
        let env = game.appendingPathComponent("env.txt")
        try Data(("DM_ROMFS_OVERLAY=" + game.appendingPathComponent("mods/Bar/romfs").path + "\n").utf8).write(to: env)
        let records = root.appendingPathComponent("copied-records.json")
        let original = try JSONEncoder().encode([ModRecord(folderName: "Foo", isOn: true), ModRecord(folderName: "Bar", isOn: false)])
        try original.write(to: records)
        let store = ModStore(supportFolder: game, recordsFile: records, titleID: "0100000000000000", canWrite: { true }, trash: { _ in XCTFail() }, allowsAutomaticMaintenance: false)
        XCTAssertEqual(store.mods().filter(\.isOn).map(\.folderName), ["Bar"])
        store.removeLeftoverInstalls()
        XCTAssertTrue(FileManager.default.fileExists(atPath: game.appendingPathComponent("mods/.installing-other-profile").path))
        XCTAssertEqual(try Data(contentsOf: records), original)
    }

    func testDevelopmentStartupDoesNotSweepSharedStaging() throws {
        let home = try root()
        let folder = home.appendingPathComponent("Games")
        let dev = AppDataProfile(home: home, isDevelopment: true)
        XCTAssertEqual(dev.automaticStagingFolders(appFolders: [folder]), [dev.supportRoot.appendingPathComponent("Temp")])
        let stable = AppDataProfile(home: home, isDevelopment: false)
        XCTAssertTrue(stable.automaticStagingFolders(appFolders: [folder]).contains(folder.appendingPathComponent(".nxlibrary-build/Temp")))
    }
    func testOnlyExplicitDevelopmentOperationsSurviveRestart() throws {
        let root = try root()
        let file = root.appendingPathComponent("operations.json")
        let imported = UUID(), requested = UUID()
        let first = DevelopmentOperationStore(file: file, isDevelopment: true)
        XCTAssertFalse(first.permits(.build, gameID: imported))
        try first.authorize(.build, gameID: requested)
        try first.authorize(.icon, gameID: requested)
        let restarted = DevelopmentOperationStore(file: file, isDevelopment: true)
        XCTAssertTrue(restarted.permits(.build, gameID: requested))
        XCTAssertTrue(restarted.permits(.icon, gameID: requested))
        XCTAssertFalse(restarted.permits(.build, gameID: imported))
        XCTAssertFalse(restarted.permits(.icon, gameID: imported))
    }
    func testCorruptAuthorizationFailsClosedWithoutReplacingIt() throws {
        let file = try root().appendingPathComponent("operations.json")
        try Data("broken".utf8).write(to: file)
        let store = DevelopmentOperationStore(file: file, isDevelopment: true)
        XCTAssertFalse(store.permits(.icon, gameID: UUID()))
        XCTAssertThrowsError(try store.authorize(.icon, gameID: UUID()))
        XCTAssertEqual(try String(contentsOf: file), "broken")
    }
}
