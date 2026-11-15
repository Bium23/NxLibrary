import XCTest
import ImageIO
@testable import NXLibraryCore

final class AchievementTierTests: XCTestCase {
    private func a(_ api: String, at: TimeInterval? = nil) -> SteamAchievement {
        SteamAchievement(apiName: api, name: "N-\(api)", description: "D-\(api)", hidden: false,
                         icon: nil, grayIcon: nil, unlockedAt: at.map { Date(timeIntervalSince1970: $0) })
    }

    func testThresholds() {
        XCTAssertEqual(AchievementTier.forPercent(0), .gold)
        XCTAssertEqual(AchievementTier.forPercent(9.94), .gold)
        XCTAssertEqual(AchievementTier.forPercent(10), .silver)
        XCTAssertEqual(AchievementTier.forPercent(29.94), .silver)
        XCTAssertEqual(AchievementTier.forPercent(30), .bronze)
        XCTAssertEqual(AchievementTier.forPercent(100), .bronze)
        XCTAssertNil(AchievementTier.forPercent(nil))
    }

    /// The screen prints one decimal: the tier follows the number the player reads.
    func testTierFollowsTheShownPercent() {
        XCTAssertEqual(AchievementTier.forPercent(9.96), .silver, "shown as 10.0%")
        XCTAssertEqual(AchievementTier.forPercent(9.94), .gold, "shown as 9.9%")
        XCTAssertEqual(AchievementTier.forPercent(29.96), .bronze, "shown as 30.0%")
    }

    func testBoardOrderIsRarestFirst() {
        XCTAssertEqual(AchievementTier.allCases, [.platinum, .gold, .silver, .bronze])
    }

    func testRowTierFollowsPercent() {
        let summary = AchievementSummary(achievements: [a("G"), a("X")], percents: ["G": 4])
        let rows = Dictionary(uniqueKeysWithValues: summary.rows(.all).map { ($0.id, $0) })
        XCTAssertEqual(rows["G"]?.tier, .gold)
        XCTAssertNil(rows["X"]?.tier)
    }

    func testCountsPerTier() {
        let summary = AchievementSummary(achievements: [a("U1", at: 1), a("L1"), a("U2", at: 2), a("L2")],
                                         percents: ["U1": 5, "L1": 5, "U2": 20, "L2": 50])
        XCTAssertEqual(summary.tierCounts[.gold], TierCount(unlocked: 1, total: 2))
        XCTAssertEqual(summary.tierCounts[.silver], TierCount(unlocked: 1, total: 1))
        XCTAssertEqual(summary.tierCounts[.bronze], TierCount(unlocked: 0, total: 1))
        XCTAssertEqual(summary.tierCounts[.platinum], TierCount(unlocked: 0, total: 1))
        XCTAssertTrue(summary.hasRarity)
    }

    func testPlatinumOnlyAtHundredPercent() {
        let summary = AchievementSummary(achievements: [a("A", at: 1), a("B", at: 2)], percents: ["A": 50])
        XCTAssertEqual(summary.tierCounts[.platinum], TierCount(unlocked: 1, total: 1))
    }

    func testNoAchievementsNoPlatinum() {
        let summary = AchievementSummary(achievements: [], percents: [:])
        for tier in AchievementTier.allCases {
            XCTAssertEqual(summary.tierCounts[tier], TierCount(unlocked: 0, total: 0), "\(tier)")
        }
        XCTAssertNil(summary.lastUnlockedAt)
    }

    func testUnknownRarityHasNoTierAndNoCounts() {
        let summary = AchievementSummary(achievements: [a("A", at: 1), a("B")], percents: [:])
        XCTAssertTrue(summary.rows(.all).allSatisfy { $0.tier == nil })
        for tier in [AchievementTier.gold, .silver, .bronze] {
            XCTAssertEqual(summary.tierCounts[tier], TierCount(unlocked: 0, total: 0), "\(tier)")
        }
        XCTAssertEqual(summary.tierCounts[.platinum], TierCount(unlocked: 0, total: 1))
        XCTAssertFalse(summary.hasRarity)
    }

    func testLastUnlockedIsNewest() {
        let summary = AchievementSummary(achievements: [a("A", at: 10), a("B", at: 20), a("C")], percents: [:])
        XCTAssertEqual(summary.lastUnlockedAt, Date(timeIntervalSince1970: 20))
    }

    func testDisplayNamesAreTheClassicOnes() {
        let english = AppLocale(language: .english, region: "US")
        XCTAssertEqual(AchievementTier.allCases.map { $0.displayName(context: english) },
                       ["Platinum", "Gold", "Silver", "Bronze"])
        let italian = AppLocale(language: .italian, region: "IT")
        XCTAssertEqual(AchievementTier.allCases.map { $0.displayName(context: italian) },
                       ["Platino", "Oro", "Argento", "Bronzo"])
    }

    func testEveryTierHasArt() throws {
        for tier in AchievementTier.allCases {
            let url = try XCTUnwrap(tier.imageURL, "\(tier)")
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), "\(tier)")
            let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            XCTAssertGreaterThanOrEqual(props[kCGImagePropertyPixelWidth] as? Int ?? 0, 512, "\(tier)")
            XCTAssertGreaterThanOrEqual(props[kCGImagePropertyPixelHeight] as? Int ?? 0, 512, "\(tier)")
        }
    }
}
