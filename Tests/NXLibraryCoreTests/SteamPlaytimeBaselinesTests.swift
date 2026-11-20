import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class SteamPlaytimeBaselinesTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory.appendingPathComponent("SteamPlaytime-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    private func snapshot(account: UInt32 = 1, _ entries: [UInt32: (Int, TimeInterval?)]) -> SteamPlaytimeSnapshot {
        SteamPlaytimeSnapshot(accountID: account, entries: entries.mapValues {
            SteamPlaytimeEntry(minutes: $0.0, lastPlayed: $0.1.map(date))
        })
    }

    func testFirstSnapshotSetsSeenAtNow() {
        var baselines = SteamPlaytimeBaselines(fileURL: url)
        XCTAssertTrue(baselines.apply(snapshot([440: (75, 500)]), now: date(1_000)))
        XCTAssertEqual(baselines.accountID, 1)
        XCTAssertEqual(baselines.byAppID[440], SteamPlaytimeBaseline(appID: 440, minutes: 75, lastPlayed: date(500), seenAt: date(1_000)))
    }

    func testSameMinutesKeepsSeenAt() {
        var baselines = SteamPlaytimeBaselines(fileURL: url)
        baselines.apply(snapshot([440: (75, 500)]), now: date(1_000))
        XCTAssertFalse(baselines.apply(snapshot([440: (75, 500)]), now: date(2_000)))
        XCTAssertTrue(baselines.apply(snapshot([440: (75, 1_500)]), now: date(3_000)))
        XCTAssertEqual(baselines.byAppID[440]?.seenAt, date(1_000))
        XCTAssertEqual(baselines.byAppID[440]?.lastPlayed, date(1_500))
    }

    func testNewMinutesResetSeenAt() {
        var baselines = SteamPlaytimeBaselines(fileURL: url)
        baselines.apply(snapshot([440: (75, 500)]), now: date(1_000))
        XCTAssertTrue(baselines.apply(snapshot([440: (80, 500)]), now: date(2_000)))
        XCTAssertEqual(baselines.byAppID[440]?.minutes, 80)
        XCTAssertEqual(baselines.byAppID[440]?.seenAt, date(2_000))
        XCTAssertTrue(baselines.apply(snapshot([440: (10, 500)]), now: date(3_000)), "Steam is the source of truth, even going down")
        XCTAssertEqual(baselines.byAppID[440]?.minutes, 10)
        XCTAssertEqual(baselines.byAppID[440]?.seenAt, date(3_000))
    }

    func testAnotherAccountStartsOver() {
        var baselines = SteamPlaytimeBaselines(fileURL: url)
        baselines.apply(snapshot(account: 1, [440: (75, nil), 10: (5, nil)]), now: date(1_000))
        XCTAssertTrue(baselines.apply(snapshot(account: 2, [440: (75, nil)]), now: date(2_000)))
        XCTAssertEqual(baselines.accountID, 2)
        XCTAssertEqual(Set(baselines.byAppID.keys), [440])
        XCTAssertEqual(baselines.byAppID[440]?.seenAt, date(2_000))
    }

    func testAppsMissingFromSnapshotAreDropped() {
        var baselines = SteamPlaytimeBaselines(fileURL: url)
        baselines.apply(snapshot([440: (75, nil), 10: (5, nil)]), now: date(1_000))
        XCTAssertTrue(baselines.apply(snapshot([440: (75, nil)]), now: date(2_000)))
        XCTAssertNil(baselines.byAppID[10])
    }

    func testSaveAndReloadRoundTrip() throws {
        var baselines = SteamPlaytimeBaselines(fileURL: url)
        baselines.apply(snapshot([440: (75, 500)]), now: date(1_000))
        try baselines.save()
        XCTAssertEqual(SteamPlaytimeBaselines(fileURL: url), baselines)
    }

    func testBrokenFileLoadsEmpty() throws {
        try Data("not json".utf8).write(to: url)
        let baselines = SteamPlaytimeBaselines(fileURL: url)
        XCTAssertNil(baselines.accountID)
        XCTAssertTrue(baselines.byAppID.isEmpty)
    }

    func testExternalMapsOnlyCatalogSteamGames() {
        var baselines = SteamPlaytimeBaselines(fileURL: url)
        baselines.apply(snapshot([440: (75, 500), 10: (5, nil)]), now: date(1_000))
        let steam = CatalogGame(steam: SteamCatalogGame(appID: 440, name: "Steam game"))
        let switchGame = CatalogGame(nxnative: PortedGame(name: "Switch", url: URL(fileURLWithPath: "/tmp/Switch.app"),
                                                          platform: .macApp, sizeBytes: 1,
                                                          modificationDate: date(0), bundleId: "org.nxnative.x", titleId: "0100000000010000"))
        XCTAssertEqual(baselines.external(for: [steam, switchGame]),
                       [steam.id: ExternalPlaytime(duration: 75 * 60, lastPlayed: date(500), since: date(1_000))])
    }

    // Steam keeps whole minutes: when its value rises, up to a minute Arcane already showed is kept.
    func testRisingMinutesKeepUpToAMinuteAlreadyShown() {
        var baselines = SteamPlaytimeBaselines(fileURL: url)
        baselines.apply(snapshot([440: (75, nil)]), now: date(1_000))
        baselines.apply(snapshot([440: (76, nil)]), now: date(2_000), previousTotals: [440: 75 * 60 + 90])
        XCTAssertEqual(baselines.byAppID[440]?.carry, 30)
        let steam = CatalogGame(steam: SteamCatalogGame(appID: 440, name: "Steam game"))
        XCTAssertEqual(baselines.external(for: [steam])[steam.id]?.duration, 76 * 60 + 30)

        baselines.apply(snapshot([440: (77, nil)]), now: date(3_000), previousTotals: [440: 76 * 60 + 500])
        XCTAssertEqual(baselines.byAppID[440]?.carry, 60, "a bigger gap is Steam's call")
    }

    func testCarryStaysWithTheSameMinutesAndResetsOtherwise() {
        var baselines = SteamPlaytimeBaselines(fileURL: url)
        baselines.apply(snapshot([440: (75, nil)]), now: date(1_000))
        baselines.apply(snapshot([440: (76, nil)]), now: date(2_000), previousTotals: [440: 75 * 60 + 90])
        baselines.apply(snapshot([440: (76, 1_500)]), now: date(2_500), previousTotals: [440: 99_999])
        XCTAssertEqual(baselines.byAppID[440]?.carry, 30)
        baselines.apply(snapshot([440: (10, nil)]), now: date(3_000), previousTotals: [440: 76 * 60 + 30])
        XCTAssertEqual(baselines.byAppID[440]?.carry, 0, "a lower value is Steam's reset")
        baselines.apply(snapshot([440: (11, nil)]), now: date(4_000), previousTotals: [440: 11 * 60 + 30])
        baselines.apply(snapshot(account: 2, [440: (12, nil)]), now: date(5_000), previousTotals: [440: 12 * 60 + 30])
        XCTAssertEqual(baselines.byAppID[440]?.carry, 0, "another account starts over")
    }

    func testFilesWithoutCarryStillLoad() throws {
        let json = #"{"accountID":1,"baselines":[{"appID":440,"minutes":75,"seenAt":1000}]}"#
        try Data(json.utf8).write(to: url)
        let baselines = SteamPlaytimeBaselines(fileURL: url)
        XCTAssertEqual(baselines.byAppID[440]?.carry, 0)
        XCTAssertEqual(baselines.byAppID[440]?.minutes, 75)
    }
}
