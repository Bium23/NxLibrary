import XCTest
@testable import NXLibraryCore

final class SpotlightPageTests: XCTestCase {
    // MARK: - Description excerpt

    func testShortDescriptionIsKept() {
        let short = "A short line."
        XCTAssertEqual(DescriptionExcerpt.make(short, limit: 100), .init(text: short, truncated: false))
    }

    func testLongDescriptionStopsAtAParagraph() {
        let first = "Step into a world of adventure\nForget everything you know. Travel across vast fields."
        let text = first + "\n\nFeatures:\nExplore the wilds of Hyrule any way you like. Climb towers."
        let excerpt = DescriptionExcerpt.make(text, limit: 120)
        XCTAssertEqual(excerpt.text, first)
        XCTAssertTrue(excerpt.truncated)
    }

    func testOneLongParagraphStopsAtASentence() {
        let text = "First sentence is here. Second sentence follows it! Third one runs on and on past the limit for sure."
        let excerpt = DescriptionExcerpt.make(text, limit: 60)
        XCTAssertEqual(excerpt.text, "First sentence is here. Second sentence follows it!")
        XCTAssertTrue(excerpt.truncated)
    }

    func testNoSentenceEndCutsAtAWord() {
        let text = String(repeating: "word ", count: 40)
        let excerpt = DescriptionExcerpt.make(text, limit: 23)
        XCTAssertEqual(excerpt.text, "word word word word…")
        XCTAssertTrue(excerpt.truncated)
    }

    // MARK: - Page scroll

    /// Window 1000 high, hints clearance 130, About at 900 and More at 1500 from the page top, page ends at 1900.
    func testMoreRestsWithThePageEndAboveTheHints() {
        let rest = SpotlightPageScroll.resting(first: -324, aboutTop: 900, moreTop: 1500, pageBottom: 1900,
                                               top: 150, viewport: 1000, bottomInset: 130)
        XCTAssertEqual(rest.actions, -750, "About this game comes up to 150")
        XCTAssertEqual(rest.more, -1030, "the page's end sits 130 above the window's bottom, not More at 150")
        XCTAssertGreaterThan(rest.more, 150 - 1500)
    }

    func testShortPageNeverScrollsPastItsEnd() {
        let rest = SpotlightPageScroll.resting(first: -324, aboutTop: 700, moreTop: 1000, pageBottom: 1300,
                                               top: 150, viewport: 1000, bottomInset: 130)
        XCTAssertEqual(rest.actions, -430, "the page's end limits Build & Sources too")
        XCTAssertEqual(rest.more, -430)
    }

    func testTallMoreBandStillComesUpToTheTop() {
        let rest = SpotlightPageScroll.resting(first: -324, aboutTop: 900, moreTop: 1500, pageBottom: 3000,
                                               top: 150, viewport: 1000, bottomInset: 130)
        XCTAssertEqual(rest.more, -1350)
    }

    func testRestsNeverRiseAboveThePills() {
        let rest = SpotlightPageScroll.resting(first: -324, aboutTop: 300, moreTop: nil, pageBottom: 500,
                                               top: 150, viewport: 1000, bottomInset: 130)
        XCTAssertEqual(rest.actions, -324)
        XCTAssertEqual(rest.more, -324)
    }
}
