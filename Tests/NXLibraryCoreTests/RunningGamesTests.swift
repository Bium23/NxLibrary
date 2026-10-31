import XCTest
@testable import NXLibraryCore

final class RunningGamesTests: XCTestCase {
    private func game(_ name: String, bundleId: String? = nil, titleId: String? = nil) -> PortedGame {
        var game = PortedGame(name: name, url: URL(fileURLWithPath: "/tmp/\(name).app"),
                              platform: .macApp, sizeBytes: 1, modificationDate: Date(),
                              bundleId: bundleId, titleId: titleId)
        game.status = .built
        return game
    }

    func testEffectiveBundleIdPrefersStoredThenNxnativeDefault() {
        XCTAssertEqual(game("A", bundleId: "org.example.a", titleId: "0100ABCD").effectiveBundleId,
                       "org.example.a")
        XCTAssertEqual(game("B", bundleId: nil, titleId: "0100ABCD").effectiveBundleId,
                       "org.nxnative.0100abcd")
        XCTAssertEqual(game("C", bundleId: "", titleId: "0100ABCD").effectiveBundleId,
                       "org.nxnative.0100abcd")
        XCTAssertNil(game("D", bundleId: nil, titleId: nil).effectiveBundleId)
        XCTAssertNil(game("E", bundleId: "", titleId: "").effectiveBundleId)
    }

    func testMatchesByStoredBundleId() {
        let zelda = game("Zelda", bundleId: "org.nxnative.zelda")
        let mario = game("Mario", bundleId: "org.nxnative.mario")
        let ids = RunningGames.matchingIDs(in: [zelda, mario],
                                           runningBundleIDs: ["org.nxnative.zelda"])
        XCTAssertEqual(ids, [zelda.id])
    }

    func testMatchesByNxnativeDefaultWhenStoredBundleIdIsMissing() {
        let game = game("Splatoon", bundleId: nil, titleId: "0100ABCD")
        let ids = RunningGames.matchingIDs(in: [game],
                                           runningBundleIDs: ["org.nxnative.0100abcd"])
        XCTAssertEqual(ids, [game.id])
    }

    func testIgnoresUnrelatedApps() {
        let game = game("Zelda", bundleId: "org.nxnative.zelda")
        XCTAssertTrue(RunningGames.matchingIDs(in: [game],
                                               runningBundleIDs: ["com.apple.Safari", "com.apple.finder"]).isEmpty)
    }

    func testNoRunningAppsMatchesNothing() {
        let game = game("Zelda", bundleId: "org.nxnative.zelda")
        XCTAssertTrue(RunningGames.matchingIDs(in: [game], runningBundleIDs: []).isEmpty)
    }

    func testEmptyOrMissingBundleIdsNeverMatch() {
        let empty = game("Empty", bundleId: "")
        let none = game("None", bundleId: nil, titleId: nil)
        let blankTitle = game("Blank", bundleId: nil, titleId: "")
        let ids = RunningGames.matchingIDs(in: [empty, none, blankTitle],
                                           runningBundleIDs: ["", "nil", "org.nxnative."])
        XCTAssertTrue(ids.isEmpty)
    }

    /// The running set comes from what is running, not from notifications: a game's launcher that quits from its
    /// settings window turns into a background process first, and macOS posts no "terminated" for it.
    func testTrackerEndsAnAppThatStoppedWithoutANotification() {
        var running: Set<String> = ["org.nxnative.pop", "com.apple.finder"]
        let tracker = RunningAppsTracker { running }
        XCTAssertEqual(tracker.running, ["org.nxnative.pop", "com.apple.finder"])
        running.remove("org.nxnative.pop")
        let change = tracker.refresh()
        XCTAssertEqual(change.ended, ["org.nxnative.pop"])
        XCTAssertEqual(change.started, [])
        XCTAssertEqual(tracker.running, ["com.apple.finder"])
        running.insert("org.nxnative.mario")
        XCTAssertEqual(tracker.refresh().started, ["org.nxnative.mario"])
        XCTAssertEqual(tracker.refresh().ended, [], "nothing changed")
    }
}
