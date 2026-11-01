import XCTest
@testable import NXLibraryCore

final class PendingInstallTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("NXPending-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func makeApp(_ url: URL, version: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": version,
                                                       "CFBundleIdentifier": "org.nxnative.0100000000000001",
                                                       "DMTitleID": "0100000000000001", "CFBundleName": "Game"],
                                                       format: .xml, options: 0)
        try plist.write(to: url.appendingPathComponent("Contents/Info.plist"))
    }

    private func game() -> PortedGame {
        var g = PortedGame(name: "Game", url: root.appendingPathComponent("Game.app"), platform: .macApp,
                           sizeBytes: 1, modificationDate: Date(timeIntervalSince1970: 0), versionString: "1.0.0")
        g.status = .built
        g.portingFailure = .failed
        return g
    }

    private func pending(folder: String = "A") -> PendingInstall {
        PendingInstall(tempApp: root.appendingPathComponent("Temp/\(folder)/Game.app"),
                       finalApp: root.appendingPathComponent("Game.app"),
                       record: BuildRecord(startedAt: Date(timeIntervalSince1970: 10), engineCommit: "2716f78",
                                           toolchainVerified: false, cancelled: false),
                       toolchain: ToolchainInfo(engineCommit: "2716f78", verified: false, note: "Untested"))
    }

    func testPortedGameKeepsPendingInstallAcrossSaves() throws {
        var g = game()
        g.pendingInstall = pending()
        let decoded = try JSONDecoder().decode(PortedGame.self, from: JSONEncoder().encode(g))
        XCTAssertEqual(decoded.pendingInstall, pending())
        g.pendingInstall = nil
        XCTAssertNil(try JSONDecoder().decode(PortedGame.self, from: JSONEncoder().encode(g)).pendingInstall)
    }

    func testRecordInstalledBuildUpdatesTheLibraryFields() {
        var g = game()
        g.pendingInstall = pending()
        let p = pending()
        let app = root.appendingPathComponent("New.app")
        g.recordInstalledBuild(p.record, toolchain: p.toolchain, at: app, version: "1.2.0",
                               date: Date(timeIntervalSince1970: 99))
        XCTAssertEqual(g.url, app)
        XCTAssertEqual(g.status, .built)
        XCTAssertEqual(g.versionString, "1.2.0")
        XCTAssertEqual(g.modificationDate, Date(timeIntervalSince1970: 99))
        XCTAssertEqual(g.lastBuild?.engineCommit, "2716f78")
        XCTAssertEqual(g.toolchain.note, "Untested")
        XCTAssertNil(g.portingFailure)
        XCTAssertNil(g.pendingInstall)
        g.recordInstalledBuild(p.record, toolchain: p.toolchain, at: app, version: nil, date: Date())
        XCTAssertEqual(g.versionString, "1.2.0", "an app without a version keeps the last known one")
    }

    func testInstallReplacesTheAppAndRemovesTheFolder() throws {
        var g = game()
        let p = pending()
        try makeApp(p.finalApp, version: "1.0.0")
        try makeApp(p.tempApp, version: "1.2.0")
        g.pendingInstall = p
        XCTAssertEqual(try PendingInstaller.install(&g, now: Date(timeIntervalSince1970: 50)), .installed)
        XCTAssertEqual(BuildOutputInstaller.version(of: p.finalApp), "1.2.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: p.folder.path))
        XCTAssertNil(g.pendingInstall)
        XCTAssertEqual(g.versionString, "1.2.0")
        XCTAssertEqual(g.lastBuild?.engineCommit, "2716f78")
    }

    func testInstallDropsAHeldAppThatIsGone() throws {
        var g = game()
        g.pendingInstall = pending()
        XCTAssertEqual(try PendingInstaller.install(&g), .gone)
        XCTAssertNil(g.pendingInstall)
        XCTAssertEqual(g.versionString, "1.0.0")
        XCTAssertNil(g.lastBuild)
    }

    func testInstallWithoutPendingDoesNothing() throws {
        var g = game()
        XCTAssertNil(try PendingInstaller.install(&g))
    }

    func testFailedInstallKeepsThePendingInstall() throws {
        var g = game()
        let p = pending()
        try makeApp(p.tempApp, version: "1.2.0")
        try FileManager.default.createDirectory(at: p.finalApp, withIntermediateDirectories: true) // not an app
        g.pendingInstall = p
        XCTAssertThrowsError(try PendingInstaller.install(&g))
        XCTAssertEqual(g.pendingInstall, p)
    }

    func testReloadAndRescanFinishAnAlreadyPublishedPendingBuild() throws {
        let p = pending()
        try makeApp(p.finalApp, version: "1.0.0")
        try makeApp(p.tempApp, version: "1.2.0")
        let importer = ImportService()
        func scanned() -> [PortedGame] {
            importer.scan(directories: [root]).map { importer.makeGame(from: $0) }
        }
        let storeDirectory = root.appendingPathComponent("catalog")
        let store = LibraryStore(directory: storeDirectory)
        var g = try XCTUnwrap(scanned().first)
        g.status = .built
        g.pendingInstall = p
        g.portingFailure = .failed
        g.portingFailureReason = PortingFailureReason(kind: .diskFull, detail: "Previous failure")
        g.settings.metalHUD = true
        try store.save(LibraryFile(games: [g]))
        XCTAssertEqual(try store.merge(scanned: scanned()).games.first?.pendingInstall, p)

        var io = BuildInstallIO()
        io.afterPublish = { throw CocoaError(.userCancelled) }
        XCTAssertThrowsError(try BuildOutputInstaller.install(tempApp: p.tempApp, finalApp: p.finalApp, io: io))
        XCTAssertEqual(BuildOutputInstaller.version(of: p.finalApp), "1.2.0")
        // Simulate termination after the bundle was published and staging was
        // cleaned, but before the new build record reached the catalog.
        try FileManager.default.removeItem(at: p.folder)
        let reopened = LibraryStore(directory: storeDirectory)
        g = try XCTUnwrap(try reopened.merge(scanned: scanned()).games.first)
        XCTAssertEqual(g.pendingInstall, p)
        XCTAssertEqual(try PendingInstaller.install(&g), .installed)
        XCTAssertNil(g.pendingInstall)
        XCTAssertNil(g.portingFailure)
        XCTAssertNil(g.portingFailureReason)
        XCTAssertEqual(g.versionString, "1.2.0")
        XCTAssertEqual(g.lastBuild, p.record)
        XCTAssertEqual(g.toolchain, p.toolchain)
        XCTAssertTrue(g.settings.metalHUD)
        try reopened.save(LibraryFile(games: [g]))
        g = try XCTUnwrap(try reopened.merge(scanned: scanned()).games.first)
        XCTAssertNil(try PendingInstaller.install(&g))
        XCTAssertEqual(g.lastBuild, p.record)
        XCTAssertEqual(BuildOutputInstaller.version(of: p.finalApp), "1.2.0")
    }

    func testHoldingAgainDiscardsTheEarlierHeldBuild() throws {
        var g = game()
        let first = pending(folder: "A"), second = pending(folder: "B")
        try makeApp(first.tempApp, version: "1.1.0")
        try makeApp(second.tempApp, version: "1.2.0")
        PendingInstaller.hold(first, for: &g)
        PendingInstaller.hold(second, for: &g)
        XCTAssertEqual(g.pendingInstall, second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.tempApp.path))
        PendingInstaller.discard(&g)
        XCTAssertNil(g.pendingInstall)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.folder.path))
    }

    func testWaitingCopy() {
        XCTAssertEqual(PendingInstall.stageName, "Ready: installs when you quit the game")
        XCTAssertEqual(PendingInstall.title, "Ready when you quit")
        XCTAssertEqual(PendingInstall.message(gameName: "Game"),
                       "Game is open, so the new app waits beside it and replaces it as soon as you quit the game.")
    }

    func testKeptFoldersAreThePendingOnes() {
        var a = game(), b = game()
        a.pendingInstall = pending(folder: "A")
        b.pendingInstall = nil
        XCTAssertEqual(PendingInstaller.keptFolders([a, b]), [pending(folder: "A").folder.standardizedFileURL.path])
    }
}
