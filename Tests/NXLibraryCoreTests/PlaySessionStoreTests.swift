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
}
