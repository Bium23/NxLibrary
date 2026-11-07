import XCTest
@testable import NXLibraryCore

final class PlaySessionStoreTests: XCTestCase {
    private var now: Date!
    private var url: URL!

    override func setUp() {
        super.setUp()
        now = Date(timeIntervalSince1970: 1_000)
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXSessions-\(UUID().uuidString).json")
    }

    private func game(_ name: String = "Game",
                      titleId: String = "0100000000010000",
                      bundleId: String = "org.nxnative.0100000000010000") -> PortedGame {
        PortedGame(name: name,
                   url: URL(fileURLWithPath: "/tmp/\(name).app"),
                   platform: .macApp,
                   sizeBytes: 1,
                   modificationDate: Date(timeIntervalSince1970: 0),
                   bundleId: bundleId,
                   titleId: titleId)
    }

    private func store() -> PlaySessionStore {
        PlaySessionStore(fileURL: url, now: { [unowned self] in self.now })
    }

    func testStartAndEnd() {
        let store = store()
        let game = game()
        XCTAssertTrue(store.start(for: game))
        XCTAssertTrue(store.isRunning(gameID: game.id))
        now = now.addingTimeInterval(3600)
        store.end(gameID: game.id)
        XCTAssertFalse(store.isRunning(gameID: game.id))
        XCTAssertEqual(store.totalDuration(for: game.id), 3600, accuracy: 0.001)
        XCTAssertEqual(store.lastPlayed(for: game.id), Date(timeIntervalSince1970: 1_000))
    }

    func testDuplicateStartIsRejected() {
        let store = store()
        let game = game()
        XCTAssertTrue(store.start(for: game))
        now = now.addingTimeInterval(10)
        XCTAssertFalse(store.start(for: game))
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testDanglingSessionClosesAtHeartbeat() {
        let store = store()
        let game = game()
        XCTAssertTrue(store.start(for: game))
        now = now.addingTimeInterval(60)
        store.heartbeat(for: game.id)
        now = now.addingTimeInterval(600)
        store.reconcile(runningBundleIDs: [])
        XCTAssertFalse(store.isRunning(gameID: game.id))
        XCTAssertEqual(store.totalDuration(for: game.id), 60, accuracy: 0.001)
    }

    func testReconcileKeepsRunningGame() {
        let store = store()
        let game = game()
        XCTAssertTrue(store.start(for: game))
        now = now.addingTimeInterval(90)
        store.reconcile(runningBundleIDs: [game.bundleId!])
        XCTAssertTrue(store.isRunning(gameID: game.id))
        XCTAssertEqual(store.totalDuration(for: game.id), 90, accuracy: 0.001)
    }

    func testSessionUsesEffectiveBundleIdWhenStoredIdIsMissing() {
        let store = store()
        var game = game()
        game.bundleId = nil
        XCTAssertTrue(store.start(for: game))
        now = now.addingTimeInterval(60)
        store.reconcile(runningBundleIDs: ["org.nxnative.0100000000010000"])
        XCTAssertTrue(store.isRunning(gameID: game.id))
        now = now.addingTimeInterval(30)
        store.end(bundleID: "org.nxnative.0100000000010000")
        XCTAssertFalse(store.isRunning(gameID: game.id))
        XCTAssertEqual(store.totalDuration(for: game.id), 90, accuracy: 0.001)
    }

    func testPersistsAcrossInstances() {
        let game = game()
        let first = store()
        XCTAssertTrue(first.start(for: game))
        now = now.addingTimeInterval(120)
        first.end(gameID: game.id)
        let second = store()
        XCTAssertEqual(second.totalDuration(for: game.id), 120, accuracy: 0.001)
    }

    func testCorruptFileFallsBackToEmpty() throws {
        try Data("nope".utf8).write(to: url)
        let store = store()
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNotNil(store.loadError)
    }

    func testEndByBundleIDReturnsTheSessionsItEnded() {
        let store = store()
        let game = game()
        XCTAssertTrue(store.start(for: game))
        now = now.addingTimeInterval(95)
        let ended = store.end(bundleID: "org.nxnative.0100000000010000")
        XCTAssertEqual(ended.map(\.gameID), [game.id])
        XCTAssertEqual(ended.first?.duration ?? 0, 95, accuracy: 0.001)
        XCTAssertTrue(store.end(bundleID: "org.nxnative.0100000000010000").isEmpty)
    }

    private func play(_ game: PortedGame, for seconds: TimeInterval, in store: PlaySessionStore) {
        XCTAssertTrue(store.start(for: game))
        now = now.addingTimeInterval(seconds)
        store.end(gameID: game.id)
        now = now.addingTimeInterval(10)
    }

    func testTotalAndLastPlayedSurviveTrimming() {
        let store = store()
        let old = game("Old", titleId: "0100000000020000", bundleId: "org.nxnative.0100000000020000")
        let busy = game("Busy")
        let oldStart = now!
        play(old, for: 3600, in: store)
        for _ in 0..<250 { play(busy, for: 60, in: store) }

        XCTAssertLessThanOrEqual(store.sessions.count, 200)
        XCTAssertFalse(store.sessions.contains { $0.gameID == old.id })
        XCTAssertEqual(store.totalDuration(for: old.id), 3600, accuracy: 0.001)
        XCTAssertEqual(store.lastPlayed(for: old.id), oldStart)
        XCTAssertEqual(store.totalDuration(for: busy.id), 250 * 60, accuracy: 0.001)

        let reloaded = self.store()
        XCTAssertNil(reloaded.loadError)
        XCTAssertEqual(reloaded.totalDuration(for: old.id), 3600, accuracy: 0.001)
        XCTAssertEqual(reloaded.lastPlayed(for: old.id), oldStart)
        XCTAssertEqual(reloaded.totalDuration(for: busy.id), 250 * 60, accuracy: 0.001)
    }

    func testTrimmingKeepsRunningSession() {
        let store = store()
        let running = game("Running", titleId: "0100000000020000", bundleId: "org.nxnative.0100000000020000")
        let busy = game("Busy")
        XCTAssertTrue(store.start(for: running))
        for _ in 0..<250 { play(busy, for: 60, in: store) }
        XCTAssertTrue(store.isRunning(gameID: running.id))
        store.end(gameID: running.id)
        XCTAssertEqual(store.totalDuration(for: running.id), 250 * 70, accuracy: 0.001)
    }

    func testLoadsLegacyArrayFile() throws {
        let game = game()
        let session = PlaySession(gameID: game.id, titleID: "0100000000010000",
                                  bundleID: game.bundleId, startedAt: now,
                                  endedAt: now.addingTimeInterval(300),
                                  lastHeartbeatAt: now.addingTimeInterval(300))
        try JSONEncoder().encode([session]).write(to: url)
        let store = store()
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.sessions, [session])
        XCTAssertEqual(store.totalDuration(for: game.id), 300, accuracy: 0.001)
        XCTAssertEqual(store.lastPlayed(for: game.id), now)
    }
    /// NX Library 0.1.4 and earlier read this file as a bare array; it must stay one
    /// so switching between app versions keeps the history.
    func testSessionsFileStaysReadableByOlderVersions() throws {
        let store = store()
        let busy = game("Busy")
        for _ in 0..<205 { play(busy, for: 60, in: store) }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([PlaySession].self, from: data)
        XCTAssertEqual(decoded, store.sessions)
    }
}
