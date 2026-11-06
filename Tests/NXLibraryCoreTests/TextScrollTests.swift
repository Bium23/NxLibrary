import CoreGraphics
import XCTest
@testable import NXLibraryCore

/// A mod panel's column scrolled inside the panel: Read more opens the whole description, and the wheel, the
/// trackpad and the controller move the column within its ends.
final class TextScrollTests: XCTestCase {
    func testReadMoreOpensTheWholeDescription() {
        // Collapsed: eight lines, or the whole text when it is shorter.
        XCTAssertEqual(TextScroll.windowHeight(text: 1200, collapsed: 160, expanded: false), 160)
        XCTAssertEqual(TextScroll.windowHeight(text: 90, collapsed: 160, expanded: false), 90)
        // Read more: all of it; the panel's column scrolls to it.
        XCTAssertEqual(TextScroll.windowHeight(text: 1200, collapsed: 160, expanded: true), 1200)
    }

    /// The window moves as little as it can to show a row whole, or a row's top when the row is taller.
    func testRevealMovesTheWindowJustEnoughToShowARow() {
        var scroll = TextScroll()
        scroll.setLayout(content: 2000, visible: 500)
        XCTAssertFalse(scroll.reveal(100...200), "a row in view does not move it")
        XCTAssertTrue(scroll.reveal(700...800))
        XCTAssertEqual(scroll.offset, 300)
        XCTAssertTrue(scroll.reveal(250...350))
        XCTAssertEqual(scroll.offset, 250)
        XCTAssertTrue(scroll.reveal(1000...1700))
        XCTAssertEqual(scroll.offset, 1000)
    }

    /// Down reads what lies between the window and the next row a step at a time; once that row is within a step,
    /// the focus moves to it and it shows whole. Up does the same upward; past the first or last row the rest of the
    /// column scrolls.
    func testAStepReadsTheTextBeforeTheNextRow() {
        var scroll = TextScroll()
        scroll.setLayout(content: 2000, visible: 500)
        // Show less at the end of a long description, then two files.
        let rows: [ClosedRange<CGFloat>] = [1200...1240, 1300...1380, 1390...1470]
        XCTAssertEqual(scroll.step(down: true, focus: 0, rows: rows), .scrolled)
        XCTAssertEqual(scroll.offset, 350)
        XCTAssertEqual(scroll.step(down: true, focus: 0, rows: rows), .scrolled)
        XCTAssertEqual(scroll.offset, 700)
        XCTAssertEqual(scroll.step(down: true, focus: 0, rows: rows), .focus(1))
        XCTAssertEqual(scroll.offset, 880)
        XCTAssertEqual(scroll.step(down: true, focus: 1, rows: rows), .focus(2))
        XCTAssertEqual(scroll.offset, 970)
        XCTAssertEqual(scroll.step(down: true, focus: 2, rows: rows), .scrolled, "past the last row the rest scrolls")
        XCTAssertEqual(scroll.offset, 1320)
        XCTAssertEqual(scroll.step(down: false, focus: 2, rows: rows), .focus(1))
        XCTAssertEqual(scroll.offset, 1300)
        XCTAssertEqual(scroll.step(down: false, focus: 1, rows: rows), .focus(0))
        XCTAssertEqual(scroll.offset, 1200)
        XCTAssertEqual(scroll.step(down: false, focus: 0, rows: rows), .scrolled, "above the first row the text scrolls back")
        XCTAssertEqual(scroll.offset, 850)
        scroll.reset()
        XCTAssertEqual(scroll.step(down: false, focus: 0, rows: rows), .none)
    }

    /// Rows already in view: a step only moves the focus.
    func testAStepAmongRowsInViewOnlyMovesTheFocus() {
        var scroll = TextScroll()
        scroll.setLayout(content: 600, visible: 600)
        let rows: [ClosedRange<CGFloat>] = [300...340, 350...430, 440...520]
        XCTAssertEqual(scroll.step(down: true, focus: 0, rows: rows), .focus(1))
        XCTAssertEqual(scroll.step(down: false, focus: 1, rows: rows), .focus(0))
        XCTAssertEqual(scroll.step(down: true, focus: 2, rows: rows), .none)
        XCTAssertEqual(scroll.offset, 0)
    }

    func testScrollStaysWithinTheTextsEnds() {
        var scroll = TextScroll()
        scroll.setLayout(content: 1200, visible: 500)
        XCTAssertEqual(scroll.reach, 700)
        XCTAssertTrue(scroll.atTop)
        XCTAssertFalse(scroll.scroll(by: -30), "above the top it does not move")
        XCTAssertTrue(scroll.scroll(by: 250))
        XCTAssertEqual(scroll.offset, 250)
        XCTAssertTrue(scroll.scroll(by: 10_000))
        XCTAssertEqual(scroll.offset, 700)
        XCTAssertTrue(scroll.atBottom)
        XCTAssertFalse(scroll.scroll(by: 5), "past the end it does not move")
    }

    /// A controller step moves most of a window, so the last lines of one step are the first of the next.
    func testControllerStepKeepsALineFromTheStepBefore() {
        var scroll = TextScroll()
        scroll.setLayout(content: 1200, visible: 500)
        XCTAssertTrue(scroll.page(down: true))
        XCTAssertEqual(scroll.offset, 350)
        XCTAssertTrue(scroll.page(down: true))
        XCTAssertEqual(scroll.offset, 700)
        XCTAssertFalse(scroll.page(down: true))
        XCTAssertTrue(scroll.page(down: false))
        XCTAssertEqual(scroll.offset, 350)
    }

    /// Show less, another mod, or a window that grew keep the scroll inside the text.
    func testANewLayoutKeepsTheScrollInsideTheText() {
        var scroll = TextScroll()
        scroll.setLayout(content: 1200, visible: 500)
        scroll.scroll(by: 700)
        scroll.setLayout(content: 1200, visible: 900)
        XCTAssertEqual(scroll.offset, 300)
        scroll.setLayout(content: 300, visible: 500)
        XCTAssertEqual(scroll.offset, 0)
        XCTAssertFalse(scroll.canScroll)
        XCTAssertTrue(scroll.atTop)
        XCTAssertTrue(scroll.atBottom)
    }

    func testResetGoesBackToTheTop() {
        var scroll = TextScroll()
        scroll.setLayout(content: 1200, visible: 500)
        scroll.scroll(by: 400)
        scroll.reset()
        XCTAssertEqual(scroll.offset, 0)
        XCTAssertEqual(scroll.reach, 700)
    }
}
