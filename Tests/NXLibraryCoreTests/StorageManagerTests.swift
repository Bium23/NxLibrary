import XCTest
@testable import NXLibraryCore

final class StorageManagerTests: XCTestCase {
    private let title = "0100000000010000"

    private func fixture() throws -> (URL, PortedGame, StorageManager) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NXStorage-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspaces/\(title)")
        let cache = workspace.appendingPathComponent("\(title)_build")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var game = PortedGame(name: "Game", url: root.appendingPathComponent("Game.app"),
                              platform: .macApp, sizeBytes: 0, modificationDate: Date(), titleId: title)
        game.workspacePath = workspace.path
        game.buildCachePath = cache.path
        let manager = StorageManager(supportRoot: root, applicationsRoot: root, logsRoot: root.appendingPathComponent("launch"))
        return (root, game, manager)
    }

    func testCacheDeletionRejectsUnrelatedFolderEvenWhenItsNameEndsInBuild() throws {
        let (root, original, manager) = try fixture()
        let unrelated = root.appendingPathComponent("personal_build")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let file = unrelated.appendingPathComponent("keep")
        try Data([1]).write(to: file)
        var game = original
        game.buildCachePath = unrelated.path
        XCTAssertThrowsError(try manager.deleteCache(for: game))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCacheDeletionRejectsSymbolicLinkToAnotherFolder() throws {
        let (root, game, manager) = try fixture()
        let cache = URL(fileURLWithPath: try XCTUnwrap(game.buildCachePath))
        try FileManager.default.removeItem(at: cache)
        let external = root.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: cache, withDestinationURL: external)
        XCTAssertThrowsError(try manager.deleteCache(for: game))
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: cache.path))
    }

    func testCacheDeletionRefusesToRemoveTheInstalledApp() throws {
        let (_, original, manager) = try fixture()
        var game = original
        game.url = URL(fileURLWithPath: try XCTUnwrap(game.buildCachePath)).appendingPathComponent("Game.app")
        try FileManager.default.createDirectory(at: game.url, withIntermediateDirectories: true)
        XCTAssertThrowsError(try manager.deleteCache(for: game))
        XCTAssertTrue(FileManager.default.fileExists(atPath: game.url.path))
    }

    func testUsageCountsSharedFilesOnceAndIncludesHiddenCacheFiles() throws {
        let (_, game, manager) = try fixture()
        let cache = URL(fileURLWithPath: try XCTUnwrap(game.buildCachePath))
        try Data(count: 20).write(to: cache.appendingPathComponent("visible"))
        try Data(count: 30).write(to: cache.appendingPathComponent(".hidden"))
        var duplicate = game
        duplicate.id = UUID()
        let usage = manager.usage(games: [game, duplicate])
        XCTAssertEqual(usage.cacheBytes, 50)
    }

    func testCacheDeletionPreservesSourcesAndInternalSymbolicLinkTargets() throws {
        let (root, original, manager) = try fixture()
        var game = original
        let cache = URL(fileURLWithPath: try XCTUnwrap(game.buildCachePath))
        let source = cache.appendingPathComponent("original.nsp")
        try Data(count: 7).write(to: source)
        game.sources = [GameFileItem(url: source, kind: .base, sizeBytes: 7)]
        XCTAssertThrowsError(try manager.deleteCache(for: game))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        game.sources = []
        let external = root.appendingPathComponent("external.nsp")
        try Data(count: 9).write(to: external)
        try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent("link.nsp"), withDestinationURL: external)
        try manager.deleteCache(for: game)
        XCTAssertEqual(try Data(contentsOf: external).count, 9)
    }

    func testMissingVolumeIsNotReportedAsSuccessfulCleanup() throws {
        let (_, original, manager) = try fixture()
        var game = original
        game.workspacePath = "/Volumes/NXStorageMissing-\(UUID())/workspace"
        game.buildCachePath = game.workspacePath! + "/\(title)_build"
        XCTAssertThrowsError(try manager.deleteCache(for: game)) { error in
            guard case StorageCleanupError.unavailable = error else { return XCTFail("Expected a disconnected drive, got \(error)") }
        }
    }

    func testRecordedCacheMustBeADirectory() throws {
        let (_, game, manager) = try fixture()
        let cache = URL(fileURLWithPath: try XCTUnwrap(game.buildCachePath))
        try FileManager.default.removeItem(at: cache)
        try Data(count: 3).write(to: cache)
        XCTAssertThrowsError(try manager.deleteCache(for: game))
        XCTAssertEqual(try Data(contentsOf: cache).count, 3)
        XCTAssertFalse(manager.snapshot(games: [game]).games[0].canDeleteCache)
    }

    func testPerGameBreakdownAndSelectiveDeletionKeepOtherGamesAndLogs() throws {
        let (root, first, manager) = try fixture()
        let firstCache = URL(fileURLWithPath: try XCTUnwrap(first.buildCachePath))
        try Data(count: 30).write(to: firstCache.appendingPathComponent("cache"))
        try FileManager.default.createDirectory(at: first.url, withIntermediateDirectories: true)
        try Data(count: 40).write(to: first.url.appendingPathComponent("game"))
        let log = root.appendingPathComponent("Logs/\(title).log")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 7).write(to: log)
        var second = first
        second.id = UUID()
        second.name = "Second"
        second.titleId = "0100000000020000"
        let secondCache = firstCache.deletingLastPathComponent().appendingPathComponent("0100000000020000_build")
        second.buildCachePath = secondCache.path
        try FileManager.default.createDirectory(at: secondCache, withIntermediateDirectories: true)
        try Data(count: 60).write(to: secondCache.appendingPathComponent("cache"))
        let snapshot = manager.snapshot(games: [first, second])
        XCTAssertEqual(snapshot.games.map(\.id), [second.id, first.id])
        XCTAssertEqual(snapshot.games[1].app, .bytes(40))
        XCTAssertEqual(snapshot.games[1].cache, .bytes(30))
        XCTAssertEqual(snapshot.games[1].logs, .bytes(7))
        XCTAssertEqual(snapshot.total.libraryBytes, 40)
        XCTAssertEqual(snapshot.total.cacheBytes, 90)
        XCTAssertTrue(try manager.deleteCache(for: first, protecting: [first, second]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondCache.path))
        XCTAssertEqual(try Data(contentsOf: log).count, 7)
        let after = manager.snapshot(games: [first, second])
        XCTAssertEqual(after.total.cacheBytes, 60)
        XCTAssertEqual(after.games.first { $0.id == first.id }?.cache, .missing)
        XCTAssertFalse(after.games.first { $0.id == first.id }!.canDeleteCache)
    }

    func testSharedCacheIsExplainedAndAnotherGamesSourcesAreProtected() throws {
        let (_, first, manager) = try fixture()
        let cache = URL(fileURLWithPath: try XCTUnwrap(first.buildCachePath))
        try Data(count: 10).write(to: cache.appendingPathComponent("data"))
        var second = first
        second.id = UUID()
        second.name = "Other build"
        let snapshot = manager.snapshot(games: [first, second])
        XCTAssertEqual(snapshot.total.cacheBytes, 10)
        XCTAssertEqual(snapshot.games.first { $0.id == first.id }?.sharedCacheWith, ["Other build"])
        second.sources = [GameFileItem(url: cache.appendingPathComponent("data"), kind: .base, sizeBytes: 10)]
        XCTAssertThrowsError(try manager.deleteCache(for: first, protecting: [second]))
        XCTAssertFalse(manager.snapshot(games: [first, second]).games.first { $0.id == first.id }!.canDeleteCache)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.appendingPathComponent("data").path))
    }

    func testMissingAndDisconnectedFoldersHaveDifferentStates() throws {
        let (_, original, manager) = try fixture()
        var game = original
        game.url = URL(fileURLWithPath: "/Volumes/NXStorageMissing-\(UUID())/Game.app")
        game.workspacePath = nil
        game.buildCachePath = nil
        let snapshot = manager.snapshot(games: [game], applicationsFolder: game.url.deletingLastPathComponent())
        XCTAssertEqual(snapshot.games[0].app, .unavailable)
        XCTAssertEqual(snapshot.games[0].cache, .missing)
        XCTAssertTrue(snapshot.hasUnavailableFiles)
        XCTAssertNil(snapshot.freeBytes)
        let local = manager.snapshot(games: [original])
        XCTAssertEqual(local.games[0].app, .missing)
        XCTAssertEqual(local.games[0].cache, .bytes(0))
        XCTAssertFalse(local.hasUnavailableFiles)
    }

    func testUnreadableCacheIsNotPresentedAsEmptyOrDeletable() throws {
        let (_, game, manager) = try fixture()
        let cache = URL(fileURLWithPath: try XCTUnwrap(game.buildCachePath))
        try Data(count: 10).write(to: cache.appendingPathComponent("data"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: cache.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cache.path) }
        let snapshot = manager.snapshot(games: [game])
        XCTAssertEqual(snapshot.games[0].cache, .unavailable)
        XCTAssertFalse(snapshot.games[0].canDeleteCache)
        XCTAssertThrowsError(try manager.deleteCache(for: game))
    }

    func testUsageAndCacheDeletion() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXStorage-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Applications/Game.app")
        let cache = root.appendingPathComponent("Workspaces/0100/0100000000010000_build")
        let logs = root.appendingPathComponent("Logs")
        let supportLogs = root.appendingPathComponent("Support/Logs")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: supportLogs, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: app.appendingPathComponent("data"))
        try Data(repeating: 1, count: 20).write(to: cache.appendingPathComponent("data"))
        try Data(repeating: 1, count: 5).write(to: logs.appendingPathComponent("0100000000010000.log"))
        try Data(repeating: 1, count: 7).write(to: supportLogs.appendingPathComponent("0100000000010000.log"))
        var game = PortedGame(name: "G", url: app, platform: .macApp,
                              sizeBytes: 0, modificationDate: Date(),
                              titleId: "0100000000010000")
        game.buildCachePath = cache.path
        game.workspacePath = cache.deletingLastPathComponent().path
        let manager = StorageManager(
            supportRoot: root.appendingPathComponent("Support"),
            applicationsRoot: root.appendingPathComponent("Applications"),
            logsRoot: logs
        )
        let usage = manager.usage(games: [game])
        XCTAssertGreaterThanOrEqual(usage.libraryBytes, 10)
        XCTAssertGreaterThanOrEqual(usage.cacheBytes, 20)
        XCTAssertGreaterThanOrEqual(usage.logsBytes, 12)
        try manager.deleteCache(for: game)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        try manager.deleteLogs(for: game)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logs.appendingPathComponent("0100000000010000.log").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: supportLogs.appendingPathComponent("0100000000010000.log").path))
        try? FileManager.default.removeItem(at: root)
    }
}
