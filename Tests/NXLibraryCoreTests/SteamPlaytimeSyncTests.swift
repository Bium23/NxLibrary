import XCTest
@testable import NXLibraryCore

final class SteamPlaytimeSyncTests: XCTestCase {
    private static let base: UInt64 = 76_561_197_960_265_728
    private var url: URL!
    private let steam = CatalogGame(steam: SteamCatalogGame(appID: 440, name: "Steam game"))

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory.appendingPathComponent("SteamPlaytimeSync-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
    private func stamp(_ seconds: TimeInterval = 1) -> SteamFileStamp {
        SteamFileStamp(file: URL(fileURLWithPath: "/tmp/localconfig.vdf"), modified: date(seconds))
    }
    private func snapshot(account: UInt32 = 1, minutes: Int = 75) -> SteamPlaytimeSnapshot {
        SteamPlaytimeSnapshot(accountID: account, entries: [440: SteamPlaytimeEntry(minutes: minutes, lastPlayed: nil)])
    }
    private func handle(_ sync: inout SteamPlaytimeSync, _ reading: SteamPlaytimeReading, games: [CatalogGame]? = nil,
                        shown: TimeInterval = 0, now: TimeInterval = 1_000) -> SteamPlaytimeSync.Result {
        sync.handle(reading, games: games ?? [steam], shownTotal: { _, _ in shown }, now: date(now))
    }

    // MARK: - Reading Steam's files

    private func write(_ text: String, to relative: String, in root: URL) throws {
        let file = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    private func account(_ root: URL, id: UInt64 = 42) throws {
        try write("\"users\" { \"\(Self.base + id)\" { \"MostRecent\" \"1\" } }", to: "config/loginusers.vdf", in: root)
    }

    func testTakeWithoutAccountOrFileIsNoAccount() throws {
        let root = try SteamTestFixture.temporary(in: self).root
        XCTAssertEqual(SteamPlaytimeReading.take(root: root, known: nil), .noAccount)
        try account(root)
        XCTAssertEqual(SteamPlaytimeReading.take(root: root, known: nil), .noAccount)
    }

    func testTakeUnreadableLoginUsersFailsWithoutAnAccount() throws {
        let root = try SteamTestFixture.temporary(in: self).root
        try write("\"users\" {", to: "config/loginusers.vdf", in: root)
        XCTAssertEqual(SteamPlaytimeReading.take(root: root, known: nil), .failed(accountID: nil))
    }

    func testTakeMalformedConfigFailsWithItsAccount() throws {
        let root = try SteamTestFixture.temporary(in: self).root
        try account(root)
        try write("", to: "userdata/42/config/localconfig.vdf", in: root)
        XCTAssertEqual(SteamPlaytimeReading.take(root: root, known: nil), .failed(accountID: 42))
    }

    func testTakeReadsOnceAndThenIsUnchanged() throws {
        let root = try SteamTestFixture.temporary(in: self).root
        try account(root)
        try write("\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" { \"440\" { \"Playtime\" \"9\" } } } } } }",
                  to: "userdata/42/config/localconfig.vdf", in: root)
        guard case .read(let snapshot, let stamp) = SteamPlaytimeReading.take(root: root, known: nil) else {
            return XCTFail("expected a reading")
        }
        XCTAssertEqual(snapshot, SteamPlaytimeSnapshot(accountID: 42, entries: [440: SteamPlaytimeEntry(minutes: 9, lastPlayed: nil)]))
        XCTAssertEqual(stamp.file.lastPathComponent, "localconfig.vdf")
        XCTAssertEqual(SteamPlaytimeReading.take(root: root, known: stamp), .unchanged(accountID: 42))
    }

    // MARK: - What a reading does

    func testReadPublishesAndSaves() {
        var sync = SteamPlaytimeSync(baselines: SteamPlaytimeBaselines(fileURL: url))
        XCTAssertEqual(handle(&sync, .read(snapshot(), stamp())),
                       .publish([steam.id: ExternalPlaytime(duration: 75 * 60, lastPlayed: nil, since: date(1_000))], save: true))
        XCTAssertEqual(sync.stamp, stamp())
        XCTAssertEqual(handle(&sync, .read(snapshot(), stamp(2)), now: 2_000),
                       .publish([steam.id: ExternalPlaytime(duration: 75 * 60, lastPlayed: nil, since: date(1_000))], save: false))
    }

    func testReadCarriesWhatWasShown() {
        var sync = SteamPlaytimeSync(baselines: SteamPlaytimeBaselines(fileURL: url))
        _ = handle(&sync, .read(snapshot(minutes: 75), stamp()))
        XCTAssertEqual(handle(&sync, .read(snapshot(minutes: 76), stamp(2)), shown: 75 * 60 + 90, now: 2_000),
                       .publish([steam.id: ExternalPlaytime(duration: 76 * 60 + 30, lastPlayed: nil, since: date(2_000))], save: true))
    }

    func testUnchangedRepublishesForTheCurrentGames() {
        var sync = SteamPlaytimeSync(baselines: SteamPlaytimeBaselines(fileURL: url))
        _ = handle(&sync, .read(snapshot(), stamp()))
        XCTAssertEqual(handle(&sync, .unchanged(accountID: 1), games: []), .publish([:], save: false))
    }

    func testFailedKeepsTheLastGoodTotals() {
        var sync = SteamPlaytimeSync(baselines: SteamPlaytimeBaselines(fileURL: url))
        _ = handle(&sync, .read(snapshot(), stamp()))
        let kept = SteamPlaytimeSync.Result.publish([steam.id: ExternalPlaytime(duration: 75 * 60, lastPlayed: nil, since: date(1_000))], save: false)
        XCTAssertEqual(handle(&sync, .failed(accountID: 1)), kept)
        XCTAssertEqual(handle(&sync, .failed(accountID: nil)), kept)
        XCTAssertEqual(sync.stamp, stamp(), "a failure does not move the stamp")
    }

    func testFailedForAnotherAccountShowsNothing() {
        var sync = SteamPlaytimeSync(baselines: SteamPlaytimeBaselines(fileURL: url))
        _ = handle(&sync, .read(snapshot(account: 1), stamp()))
        XCTAssertEqual(handle(&sync, .failed(accountID: 2)), .clear)
    }

    func testNoAccountClearsAndForgetsTheStamp() {
        var sync = SteamPlaytimeSync(baselines: SteamPlaytimeBaselines(fileURL: url))
        _ = handle(&sync, .read(snapshot(), stamp()))
        XCTAssertEqual(handle(&sync, .noAccount), .clear)
        XCTAssertNil(sync.stamp)
    }

    func testResetStampMakesTheNextReadingFull() {
        var sync = SteamPlaytimeSync(baselines: SteamPlaytimeBaselines(fileURL: url))
        _ = handle(&sync, .read(snapshot(), stamp()))
        sync.resetStamp()
        XCTAssertNil(sync.stamp)
    }

    func testFailedWithoutAnAccountStaysClearedAfterAnotherAccountWasSeen() {
        var sync = SteamPlaytimeSync(baselines: SteamPlaytimeBaselines(fileURL: url))
        _ = handle(&sync, .read(snapshot(account: 1), stamp()))
        XCTAssertEqual(handle(&sync, .failed(accountID: 2)), .clear)
        XCTAssertEqual(handle(&sync, .failed(accountID: nil)), .clear)
    }

    func testCarryIsMeasuredFromTheOldBaseline() {
        var sync = SteamPlaytimeSync(baselines: SteamPlaytimeBaselines(fileURL: url))
        _ = handle(&sync, .read(snapshot(minutes: 75), stamp()))
        var asked: ExternalPlaytime?
        let result = sync.handle(.read(snapshot(minutes: 76), stamp(2)), games: [steam],
                                 shownTotal: { _, old in asked = old; return old.duration + 90 }, now: date(2_000))
        XCTAssertEqual(asked, ExternalPlaytime(duration: 75 * 60, lastPlayed: nil, since: date(1_000)))
        XCTAssertEqual(result, .publish([steam.id: ExternalPlaytime(duration: 76 * 60 + 30, lastPlayed: nil, since: date(2_000))], save: true))
    }
}

final class SteamPlaytimeReadQueueTests: XCTestCase {
    func testOneReadAtATime() {
        var queue = SteamPlaytimeReadQueue()
        let ticket = queue.request()
        XCTAssertNotNil(ticket)
        XCTAssertNil(queue.request())
        XCTAssertNil(queue.request())
        XCTAssertTrue(queue.isReading)
    }

    func testRequestsDuringAReadReadOnceMore() throws {
        var queue = SteamPlaytimeReadQueue()
        let ticket = try XCTUnwrap(queue.request())
        _ = queue.request(); _ = queue.request()
        XCTAssertEqual(queue.finish(ticket).apply, true)
        let again = try XCTUnwrap(queue.request(), "the read after finishing starts")
        XCTAssertEqual(queue.finish(again).readAgain, false, "one more read served every request")
    }

    func testFinishWithoutRequestsStops() throws {
        var queue = SteamPlaytimeReadQueue()
        let ticket = try XCTUnwrap(queue.request())
        let result = queue.finish(ticket)
        XCTAssertTrue(result.apply)
        XCTAssertFalse(result.readAgain)
        XCTAssertFalse(queue.isReading)
    }

    func testAnInvalidatedReadIsNotAppliedAndReadsAgain() throws {
        var queue = SteamPlaytimeReadQueue()
        let ticket = try XCTUnwrap(queue.request())
        queue.invalidate()
        let result = queue.finish(ticket)
        XCTAssertFalse(result.apply)
        XCTAssertTrue(result.readAgain)
    }

    func testStoppingDropsPendingRequests() throws {
        var queue = SteamPlaytimeReadQueue()
        let ticket = try XCTUnwrap(queue.request())
        _ = queue.request()
        queue.stop()
        XCTAssertEqual(queue.finish(ticket).apply, false)
        XCTAssertFalse(queue.isReading)
    }
}
