import XCTest
@testable import NXLibraryCore

final class GameAppDestinationTests: XCTestCase {
    private var root: URL!
    private let title = "0100000000010000"

    func testFirstUseCanPrepareTheDefaultFolderWithoutAnExtraPicker() throws {
        let home = try folder("New home")
        let apps = home.appendingPathComponent("Applications")
        try GameAppDestination.prepareInitialFolder(apps, hasExplicitChoice: false, home: home)
        XCTAssertNil(GameAppDestination.folderProblem(at: apps))
    }

    func testFirstUseNeverRecreatesAnUnavailableCustomOrConfirmedFolder() throws {
        let home = try folder("New home")
        let custom = root.appendingPathComponent("Disconnected/Games")
        try GameAppDestination.prepareInitialFolder(custom, hasExplicitChoice: false, home: home)
        XCTAssertFalse(FileManager.default.fileExists(atPath: custom.path))
        let apps = home.appendingPathComponent("Applications")
        try GameAppDestination.prepareInitialFolder(apps, hasExplicitChoice: true, home: home)
        XCTAssertFalse(FileManager.default.fileExists(atPath: apps.path))
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("NXDestination-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func app(at url: URL, titleID: String? = nil, version: String = "1") throws -> URL {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        var info = ["CFBundleIdentifier": "example.unrelated", "CFBundleShortVersionString": version]
        if let titleID { info["DMTitleID"] = titleID }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        return url
    }

    private func game(at url: URL, status: GameStatus = .notBuilt) -> PortedGame {
        var game = PortedGame(name: "Game", url: url, platform: .macApp, sizeBytes: 0,
                              modificationDate: Date(), titleId: title)
        game.status = status
        return game
    }

    func testFirstBuildInstallsIntoTheChosenFolderAndIsDiscoveredThere() throws {
        let chosen = try folder("My game apps")
        let staged = try app(at: root.appendingPathComponent("Staging/Game.app"), titleID: title)
        let destination = GameAppDestination.url(for: game(at: root.appendingPathComponent("workspace")), in: chosen)
        XCTAssertEqual(destination, chosen.appendingPathComponent("Game.app"))
        // Do not let a broken resolver write outside this test's temporary tree.
        guard destination.deletingLastPathComponent().standardizedFileURL == chosen.standardizedFileURL else { return }
        try BuildOutputInstaller.install(tempApp: staged, finalApp: destination)
        let found = ImportService().scan(directories: [chosen])
        XCTAssertEqual(found.map { $0.appURL.resolvingSymlinksInPath().path },
                       [chosen.appendingPathComponent("Game.app").resolvingSymlinksInPath().path])
        XCTAssertEqual(found.first?.titleId, title)
    }

    func testChangingFolderAffectsNewBuildsAndDoesNotMoveExistingApps() throws {
        let previous = try folder("Previous games")
        let chosen = try folder("New games")
        let installed = try app(at: previous.appendingPathComponent("Game.app"), titleID: title)
        let existing = game(at: installed, status: .built)
        XCTAssertEqual(GameAppDestination.url(for: existing, in: chosen), installed)
        XCTAssertEqual(GameAppDestination.url(name: "Other game", titleId: "0100000000020000", in: chosen),
                       chosen.appendingPathComponent("Other game.app"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: chosen.path).isEmpty)
    }

    func testRebuildStillReplacesTheExistingAppAfterFolderChange() throws {
        let previous = try folder("Previous games")
        let chosen = try folder("New games")
        let installed = try app(at: previous.appendingPathComponent("Game.app"), titleID: title)
        let staged = try app(at: root.appendingPathComponent("Staging/Game.app"), titleID: title, version: "2")
        let destination = GameAppDestination.url(for: game(at: installed, status: .built), in: chosen)
        XCTAssertEqual(destination, installed)
        try BuildOutputInstaller.install(tempApp: staged, finalApp: destination)
        XCTAssertEqual(BuildOutputInstaller.version(of: installed), "2")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: chosen.path).isEmpty)
    }

    func testMissingAppIsRebuiltIntoTheChosenFolder() throws {
        let chosen = try folder("New games")
        let missing = root.appendingPathComponent("Disconnected/Game.app")
        let destination = GameAppDestination.url(for: game(at: missing, status: .appMissing), in: chosen)
        XCTAssertEqual(destination, chosen.appendingPathComponent("Game.app"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.deletingLastPathComponent().path))
    }

    func testSourceDirectoryNamedAppIsNeverUsedAsTheDestination() throws {
        let chosen = try folder("Games")
        let source = try app(at: root.appendingPathComponent("Source.app"), titleID: title)
        var unbuilt = game(at: source)
        unbuilt.workspacePath = source.path
        XCTAssertEqual(GameAppDestination.url(for: unbuilt, in: chosen), chosen.appendingPathComponent("Game.app"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testNameCollisionsKeepUnrelatedAppsIntact() throws {
        let chosen = try folder("Games")
        let unrelated = try app(at: chosen.appendingPathComponent("Game.app"))
        let alsoUnrelated = try app(at: chosen.appendingPathComponent("Game (0100000000010000).app"))
        let destination = GameAppDestination.url(name: "Game", titleId: title, in: chosen)
        XCTAssertEqual(destination, chosen.appendingPathComponent("Game (0100000000010000) 2.app"))
        XCTAssertEqual(BuildOutputInstaller.version(of: unrelated), "1")
        XCTAssertEqual(BuildOutputInstaller.version(of: alsoUnrelated), "1")
    }

    func testSameTitleReusesItsDestinationAndNamesStayWithinTheFolder() throws {
        let chosen = try folder("Games")
        let installed = try app(at: chosen.appendingPathComponent("My-Game - Test.app"), titleID: title.lowercased())
        XCTAssertEqual(GameAppDestination.url(name: " My/Game: Test ", titleId: title, in: chosen).path, installed.path)
        XCTAssertEqual(GameAppDestination.url(name: "  ", titleId: title, in: chosen), chosen.appendingPathComponent("Game.app"))
    }

    func testUnavailableFolderIsRejectedWithoutCreatingIt() throws {
        let missing = root.appendingPathComponent("Disconnected/Games")
        XCTAssertNotNil(GameAppDestination.folderProblem(at: missing))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        let file = root.appendingPathComponent("not a folder")
        try Data().write(to: file)
        XCTAssertNotNil(GameAppDestination.folderProblem(at: file))
    }

    func testReadOnlyFolderKeepsExistingAppsDiscoverableButCannotReceiveBuilds() throws {
        let chosen = try folder("Read only games")
        _ = try app(at: chosen.appendingPathComponent("Game.app"), titleID: title)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: chosen.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: chosen.path) }
        XCTAssertNotNil(GameAppDestination.folderProblem(at: chosen))
        let imported = try XCTUnwrap(ImportService().scan(directories: [chosen]).first)
        XCTAssertTrue(ImportService().makeGame(from: imported).isPlayableLocally)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: chosen.path)
        XCTAssertNil(GameAppDestination.folderProblem(at: chosen))
    }
}
