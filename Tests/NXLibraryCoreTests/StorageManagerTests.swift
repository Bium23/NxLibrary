import XCTest
@testable import NXLibraryCore

final class StorageManagerTests: XCTestCase {
    func testUsageAndCacheDeletion() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXStorage-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Applications/Game.app")
        let cache = root.appendingPathComponent("Workspaces/0100/0100_build")
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
