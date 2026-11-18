import XCTest
import Combine
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

    func testSteamSessionIsQualifiedAndOnlyItsOwnerEndsIt() {
        let store = store()
        let steamID = UUID()
        let nx = game()
        XCTAssertTrue(store.start(gameID: steamID, sourceID: "steam-570"))
        XCTAssertFalse(store.start(gameID: steamID, sourceID: "steam-570"), "one running session per game")
        XCTAssertTrue(store.start(for: nx))
        now = now.addingTimeInterval(120)
        // An nxnative app quitting ends its own session only.
        XCTAssertEqual(store.end(bundleID: nx.bundleId).map(\.gameID), [nx.id])
        XCTAssertTrue(store.isRunning(gameID: steamID))
        store.heartbeat(for: steamID)
        now = now.addingTimeInterval(60)
        store.end(gameID: steamID)
        XCTAssertEqual(store.totalDuration(for: steamID), 180, accuracy: 0.001)
        XCTAssertEqual(store.sessions.first { $0.gameID == steamID }?.titleID, "steam-570")
        XCTAssertNil(store.sessions.first { $0.gameID == steamID }?.bundleID)
        // Reloaded from disk with the old decoder shape.
        let reloaded = PlaySessionStore(fileURL: url, now: { [unowned self] in self.now })
        XCTAssertEqual(reloaded.totalDuration(for: steamID), 180, accuracy: 0.001)
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

    func testEndByGameIDReturnsTheSessionsItEnded() {
        let store = store(), id = UUID()
        XCTAssertTrue(store.start(gameID: id, sourceID: "steam-440"))
        now = now.addingTimeInterval(120)
        let ended = store.end(gameID: id)
        XCTAssertEqual(ended.map(\.gameID), [id])
        XCTAssertEqual(ended.first?.duration ?? 0, 120, accuracy: 0.001)
        XCTAssertTrue(store.end(gameID: id).isEmpty)
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

    // MARK: - Steam's own playtime as a baseline

    private func session(_ store: PlaySessionStore, _ id: UUID, from start: TimeInterval, to end: TimeInterval?) {
        now = Date(timeIntervalSince1970: start)
        store.start(gameID: id, sourceID: "steam-440")
        guard let end else { return }
        now = Date(timeIntervalSince1970: end)
        store.end(gameID: id)
    }

    private func external(_ duration: TimeInterval = 3_600, lastPlayed: TimeInterval? = nil,
                          since: TimeInterval = 1_000) -> ExternalPlaytime {
        ExternalPlaytime(duration: duration, lastPlayed: lastPlayed.map { Date(timeIntervalSince1970: $0) },
                         since: Date(timeIntervalSince1970: since))
    }

    func testNoExternalKeepsTodaysTotals() {
        let store = store(), id = UUID()
        session(store, id, from: 1_100, to: 1_400)
        store.setExternal([:])
        XCTAssertEqual(store.totalDuration(for: id), 300, accuracy: 0.001)
        XCTAssertEqual(store.lastPlayed(for: id), Date(timeIntervalSince1970: 1_100))
    }

    func testExternalAloneIsItsTotal() {
        let store = store(), id = UUID()
        store.setExternal([id: external()])
        XCTAssertEqual(store.totalDuration(for: id), 3_600, accuracy: 0.001)
        XCTAssertNil(store.lastPlayed(for: id))
    }

    func testSessionsAfterSinceAreAdded() {
        let store = store(), id = UUID()
        session(store, id, from: 1_100, to: 1_400)
        store.setExternal([id: external()])
        XCTAssertEqual(store.totalDuration(for: id), 3_900, accuracy: 0.001)
    }

    func testSessionsBeforeSinceAreNotAdded() {
        let store = store(), id = UUID()
        session(store, id, from: 500, to: 900)
        store.setExternal([id: external()])
        XCTAssertEqual(store.totalDuration(for: id), 3_600, accuracy: 0.001)
    }

    func testStraddlingSessionCountsOnlyAfterSince() {
        let store = store(), id = UUID()
        session(store, id, from: 800, to: 1_300)
        store.setExternal([id: external()])
        XCTAssertEqual(store.totalDuration(for: id), 3_900, accuracy: 0.001)

        let running = UUID()
        session(store, running, from: 800, to: nil)
        now = Date(timeIntervalSince1970: 1_300)
        store.setExternal([running: external()])
        XCTAssertEqual(store.totalDuration(for: running), 3_900, accuracy: 0.001)
    }

    func testCarriedTimeIsIgnoredWithExternal() {
        let store = store(), id = UUID()
        for index in 0...PlaySessionStore.maxSessions {
            let start = TimeInterval(index * 10)
            session(store, id, from: start, to: start + 5)
        }
        XCTAssertFalse(store.carried.isEmpty)
        now = Date(timeIntervalSince1970: 3_000)
        store.setExternal([id: external(since: 2_002)])
        XCTAssertEqual(store.totalDuration(for: id), 3_603, accuracy: 0.001)
    }

    func testLastPlayedIsTheLaterOfBoth() {
        let store = store(), id = UUID()
        session(store, id, from: 1_100, to: 1_400)
        store.setExternal([id: external(lastPlayed: 2_000)])
        XCTAssertEqual(store.lastPlayed(for: id), Date(timeIntervalSince1970: 2_000))
        store.setExternal([id: external(lastPlayed: 900)])
        XCTAssertEqual(store.lastPlayed(for: id), Date(timeIntervalSince1970: 1_100))
    }

    // Sessions trimmed out of the recent list after Steam's value was seen still count until Steam moves on.
    func testTrimmedSessionsAfterSinceStillCount() {
        let store = store(), id = UUID()
        store.setExternal([id: external(since: 0)])
        for index in 0...PlaySessionStore.maxSessions {
            let start = TimeInterval(10 + index * 10)
            session(store, id, from: start, to: start + 5)
        }
        XCTAssertFalse(store.carried.isEmpty)
        let sessionsTotal = TimeInterval(PlaySessionStore.maxSessions + 1) * 5
        XCTAssertEqual(store.totalDuration(for: id), 3_600 + sessionsTotal, accuracy: 0.001)

        let reloaded = PlaySessionStore(fileURL: url, now: { [unowned self] in self.now })
        reloaded.setExternal([id: external(since: 0)])
        XCTAssertEqual(reloaded.totalDuration(for: id), 3_600 + sessionsTotal, accuracy: 0.001)

        store.setExternal([id: external(7_200, since: 5_000)])
        XCTAssertEqual(store.totalDuration(for: id), 7_200, accuracy: 0.001, "Steam's new value covers them")
    }

    func testTrimmedStraddlingSessionCarriesOnlyItsPartAfterSince() {
        let store = store(), id = UUID()
        store.setExternal([id: external(since: 3)])
        session(store, id, from: 0, to: 10)
        for index in 0..<PlaySessionStore.maxSessions {
            let start = TimeInterval(100 + index * 10)
            session(store, id, from: start, to: start + 5)
        }
        XCTAssertEqual(store.carried[id]?.duration, 10)
        XCTAssertEqual(store.totalDuration(for: id), 3_600 + 7 + TimeInterval(PlaySessionStore.maxSessions) * 5, accuracy: 0.001)
    }

    func testTotalWithAGivenExternalIgnoresThePublishedOne() {
        let store = store(), id = UUID()
        session(store, id, from: 1_100, to: 1_400)
        store.setExternal([id: external(10)])
        XCTAssertEqual(store.totalDuration(for: id, with: external()), 3_900, accuracy: 0.001)
        XCTAssertEqual(store.totalDuration(for: id, with: nil), 300, accuracy: 0.001)
    }

    // While Steam's totals are hidden (source off, other account, launch), trimming still keeps its part.
    func testTrimWhileTotalsAreHiddenKeepsThePartAfterTheKnownValue() {
        let store = store(), id = UUID()
        store.setTrimReferences([id: Date(timeIntervalSince1970: 0)])
        store.setExternal([:])
        for index in 0...PlaySessionStore.maxSessions {
            let start = TimeInterval(10 + index * 10)
            session(store, id, from: start, to: start + 5)
        }
        store.setExternal([id: external(since: 0)])
        XCTAssertEqual(store.totalDuration(for: id), 3_600 + TimeInterval(PlaySessionStore.maxSessions + 1) * 5, accuracy: 0.001)
    }

    func testOlderTotalsFileWithoutExternalFieldsStillLoads() throws {
        let id = UUID()
        let json = #"[{"gameID":"\#(id.uuidString)","playtime":{"duration":120,"lastPlayed":0}}]"#
        let probe = PlaySessionStore(fileURL: url, now: { [unowned self] in self.now })
        try Data(json.utf8).write(to: probe.totalsURL)
        let loaded = PlaySessionStore(fileURL: url, now: { [unowned self] in self.now })
        XCTAssertNil(loaded.loadError)
        XCTAssertEqual(loaded.carried[id], CarriedPlaytime(duration: 120, lastPlayed: Date(timeIntervalSinceReferenceDate: 0)))
    }

    func testAGameFoundAlreadyRunningIsNotAnnounced() {
        let store = store(), id = UUID()
        var started: [UUID] = []
        let token = store.starts.sink { started.append($0) }
        XCTAssertTrue(store.start(gameID: id, sourceID: "steam-440", announces: false))
        XCTAssertTrue(store.isRunning(gameID: id))
        XCTAssertEqual(started, [])
        token.cancel()
    }

    func testStartsAreAnnouncedOnce() {
        let store = store(), id = UUID()
        var started: [UUID] = []
        let token = store.starts.sink { started.append($0) }
        store.start(gameID: id, sourceID: "steam-440")
        store.start(gameID: id, sourceID: "steam-440")
        let nx = game()
        store.start(for: nx)
        XCTAssertEqual(started, [id, nx.id])
        token.cancel()
    }
}
