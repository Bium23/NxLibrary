import XCTest
@testable import NXLibraryCore

final class SpotlightPageTests: XCTestCase {
    // MARK: - Description excerpt

    func testShortDescriptionIsKept() {
        let short = "A short line."
        XCTAssertEqual(DescriptionExcerpt.make(short, minLines: 4, charsPerLine: 40), .init(text: short, truncated: false))
    }

    func testExcerptReachesTheLinesAtASentence() {
        let text = "First sentence is here. Second sentence follows it! Third one runs on and on past the limit for sure."
        let excerpt = DescriptionExcerpt.make(text, minLines: 2, charsPerLine: 30)
        XCTAssertEqual(excerpt.text, "First sentence is here. Second sentence follows it!")
        XCTAssertTrue(excerpt.truncated)
    }

    func testLineBreaksAndBlankLinesCount() {
        let text = "Title\nIntro line.\n\nBody one. Body two. Body three. Body four is long enough."
        let excerpt = DescriptionExcerpt.make(text, minLines: 3, charsPerLine: 40)
        XCTAssertEqual(excerpt.text, "Title\nIntro line.\n\nBody one.")
        XCTAssertTrue(excerpt.truncated)
    }

    func testAShortRestIsShownInFull() {
        let text = "One two three. Four."
        XCTAssertEqual(DescriptionExcerpt.make(text, minLines: 1, charsPerLine: 15), .init(text: text, truncated: false))
    }

    func testNoSentenceEndCutsAtAWord() {
        let text = String(repeating: "word ", count: 40)
        let excerpt = DescriptionExcerpt.make(text, minLines: 2, charsPerLine: 20)
        XCTAssertEqual(excerpt.text, "word word word word word word word word…")
        XCTAssertTrue(excerpt.truncated)
    }

    func testARunOnSentenceCutsAtAWord() {
        let text = "Short. " + String(repeating: "on ", count: 60) + "end."
        let excerpt = DescriptionExcerpt.make(text, minLines: 2, charsPerLine: 20)
        XCTAssertTrue(excerpt.text.hasSuffix("…"))
        XCTAssertLessThanOrEqual(excerpt.text.count, 41)
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

    func testReadMoreIsBroughtAboveTheHints() {
        XCTAssertEqual(SpotlightPageScroll.revealing(-750, bottom: 2000, viewport: 1000, bottomInset: 130), -1130)
        XCTAssertEqual(SpotlightPageScroll.revealing(-750, bottom: 1500, viewport: 1000, bottomInset: 130), -750,
                       "already visible: the page stays")
    }
}
