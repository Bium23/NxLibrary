import XCTest
@testable import NXLibraryCore

final class AchievementSummaryTests: XCTestCase {
    private func a(_ api: String, at: TimeInterval? = nil, hidden: Bool = false) -> SteamAchievement {
        SteamAchievement(apiName: api, name: "N-\(api)", description: "D-\(api)", hidden: hidden,
                         icon: "\(api).jpg", grayIcon: "\(api)-g.jpg", unlockedAt: at.map { Date(timeIntervalSince1970: $0) })
    }

    func testCountsAndPercentage() {
        let list = (0..<50).map { a("A\($0)", at: $0 < 17 ? TimeInterval($0 + 1) : nil) }
        let summary = AchievementSummary(achievements: list, percents: [:])
        XCTAssertEqual(summary.total, 50)
        XCTAssertEqual(summary.unlocked, 17)
        XCTAssertEqual(summary.percentComplete, 34)
    }

    func testCompleteOnlyWithEveryAchievementUnlocked() {
        XCTAssertTrue(AchievementSummary(achievements: [a("A", at: 1), a("B", at: 2)], percents: [:]).isComplete)
        XCTAssertFalse(AchievementSummary(achievements: [a("A", at: 1), a("B")], percents: [:]).isComplete)
        XCTAssertFalse(AchievementSummary(achievements: [], percents: [:]).isComplete)
    }

    func testEmptyIsZeroPercent() {
        XCTAssertEqual(AchievementSummary(achievements: [], percents: [:]).percentComplete, 0)
    }

    func testAllOrdersUnlockedNewestThenLockedMostCommon() {
        let summary = AchievementSummary(achievements: [a("L1"), a("U1", at: 10), a("L2"), a("U2", at: 20)],
                                         percents: ["L1": 5, "L2": 50, "U1": 1, "U2": 2])
        XCTAssertEqual(summary.rows(.all).map(\.id), ["U2", "U1", "L2", "L1"])
    }

    func testUnknownRarityGoesLast() {
        let summary = AchievementSummary(achievements: [a("X"), a("Y"), a("Z")], percents: ["Z": 3])
        XCTAssertEqual(summary.rows(.locked).map(\.id), ["Z", "X", "Y"])
        XCTAssertEqual(summary.rows(.all, order: .rarest).map(\.id), ["Z", "X", "Y"])
        XCTAssertEqual(summary.rows(.all, order: .commonest).map(\.id), ["Z", "X", "Y"])
    }

    func testFiltersSplitUnlockedAndLocked() {
        let summary = AchievementSummary(achievements: [a("L"), a("U", at: 1)], percents: [:])
        XCTAssertEqual(summary.rows(.unlocked).map(\.id), ["U"])
        XCTAssertEqual(summary.rows(.locked).map(\.id), ["L"])
    }

    func testRarestFirstIsAscendingRarity() {
        let summary = AchievementSummary(achievements: [a("A", at: 1), a("B"), a("C")], percents: ["A": 40, "B": 2, "C": 90])
        XCTAssertEqual(summary.rows(.all, order: .rarest).map(\.id), ["B", "A", "C"])
    }

    func testMostCommonFirstIsDescendingRarity() {
        let summary = AchievementSummary(achievements: [a("A", at: 1), a("B"), a("C")], percents: ["A": 40, "B": 2, "C": 90])
        XCTAssertEqual(summary.rows(.all, order: .commonest).map(\.id), ["C", "A", "B"])
    }

    /// An order sorts inside the filter: Unlocked stays the unlocked ones.
    func testOrderAppliesWithinTheFilter() {
        let summary = AchievementSummary(achievements: [a("U1", at: 1), a("U2", at: 2), a("L")],
                                         percents: ["U1": 3, "U2": 60, "L": 1])
        XCTAssertEqual(summary.rows(.unlocked, order: .rarest).map(\.id), ["U1", "U2"])
        XCTAssertEqual(summary.rows(.unlocked, order: .commonest).map(\.id), ["U2", "U1"])
        XCTAssertEqual(summary.rows(.unlocked).map(\.id), ["U2", "U1"], "default: newest first")
    }

    /// Equal rarity keeps the default order, so a re-read never shuffles ties.
    func testTiesKeepTheDefaultOrder() {
        let summary = AchievementSummary(achievements: [a("A", at: 1), a("B", at: 2), a("C")],
                                         percents: ["A": 10, "B": 10, "C": 10])
        XCTAssertEqual(summary.rows(.all, order: .rarest).map(\.id), ["B", "A", "C"])
        XCTAssertEqual(summary.rows(.all, order: .commonest).map(\.id), ["B", "A", "C"])
    }

    func testFiltersAreAllUnlockedLocked() {
        XCTAssertEqual(AchievementFilter.allCases, [.all, .unlocked, .locked])
        XCTAssertEqual(AchievementOrder.allCases, [.default, .rarest, .commonest])
    }

    func testHiddenLockedIsMaskedAndUnlockedHiddenIsNot() {
        let summary = AchievementSummary(achievements: [a("H", hidden: true), a("V", at: 1, hidden: true)], percents: [:])
        let locked = summary.rows(.locked)[0]
        XCTAssertTrue(locked.isMasked)
        XCTAssertEqual(locked.name, L10n.text("Hidden achievement"))
        XCTAssertEqual(locked.description, L10n.text("Keep playing to reveal it."))
        XCTAssertEqual(locked.icon, "H-g.jpg")
        let unlocked = summary.rows(.unlocked)[0]
        XCTAssertFalse(unlocked.isMasked)
        XCTAssertEqual(unlocked.name, "N-V")
        XCTAssertEqual(unlocked.icon, "V.jpg")
    }

    func testHiddenLockedWithoutGrayIconShowsNoIcon() {
        let hidden = SteamAchievement(apiName: "H", name: "N", description: "D", hidden: true,
                                      icon: "color.jpg", grayIcon: nil, unlockedAt: nil)
        let summary = AchievementSummary(achievements: [hidden], percents: [:])
        XCTAssertNil(summary.rows(.locked)[0].icon, "the color icon would give the secret away")
        XCTAssertTrue(summary.recentIcons.isEmpty)
    }

    /// The card locks and blurs a secret among its gray icons, as the list does.
    func testRecentIconsSayWhichAreSecret() {
        let summary = AchievementSummary(achievements: [a("A"), a("H", hidden: true)], percents: [:])
        XCTAssertEqual(summary.recentIcons.map(\.icon), ["A-g.jpg", "H-g.jpg"])
        XCTAssertEqual(summary.recentIcons.map(\.isMasked), [false, true])
    }

    func testRecentIconsFallBackToLockedGray() {
        let none = AchievementSummary(achievements: [a("A"), a("B"), a("C"), a("D")], percents: [:])
        XCTAssertEqual(none.recentIcons.map(\.icon), ["A-g.jpg", "B-g.jpg", "C-g.jpg"])
        let some = AchievementSummary(achievements: [a("A", at: 1), a("B", at: 3), a("C"), a("D", at: 2), a("E", at: 4)], percents: [:])
        XCTAssertEqual(some.recentIcons.map(\.icon), ["E.jpg", "B.jpg", "D.jpg"])
    }

    func testRecentUnlockedIconsNewestFirstCapped() {
        let list = (0..<15).map { a("U\($0)", at: TimeInterval($0 + 1)) } + [a("L")]
        let summary = AchievementSummary(achievements: list, percents: [:])
        XCTAssertEqual(summary.recentUnlockedIcons(limit: 12).count, 12)
        XCTAssertEqual(summary.recentUnlockedIcons(limit: 3), ["U14.jpg", "U13.jpg", "U12.jpg"])
    }

    func testRecentUnlockedIconsEmptyBeforeAnyUnlock() {
        let summary = AchievementSummary(achievements: [a("A"), a("B")], percents: [:])
        XCTAssertTrue(summary.recentUnlockedIcons(limit: 12).isEmpty, "locked gray icons are not 'recently unlocked'")
    }
}
