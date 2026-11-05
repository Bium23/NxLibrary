import XCTest
@testable import NXLibraryCore

final class ReleaseNotesLayoutTests: XCTestCase {
    func testNotesKeepOneEntryPerLineSoScrollingByLineStillWorks() {
        let notes = "Intro.\n\n### Engine\n- Updated **nxnative** to `4a0551e4`.\n* Star item\n• Dot item\n  - Indented item"
        let lines = ReleaseNotesLayout.lines(notes)
        XCTAssertEqual(lines.count, notes.components(separatedBy: "\n").count)
        XCTAssertEqual(lines.map(\.kind), [.text, .blank, .heading, .item, .item, .item, .item])
        XCTAssertEqual(lines[2].text, "Engine")
        XCTAssertEqual(lines[3].text, "Updated **nxnative** to `4a0551e4`.", "inline Markdown stays for the dialog")
        XCTAssertEqual(lines[6].text, "Indented item")
    }

    func testOnlyAMarkerFollowedBySpaceMakesAnItem() {
        XCTAssertEqual(ReleaseNotesLayout.lines("-flag stays text").first?.kind, .text)
        XCTAssertEqual(ReleaseNotesLayout.lines("**Bold** line").first?.kind, .text)
        XCTAssertEqual(ReleaseNotesLayout.lines("#### Deep heading").first, .init(kind: .heading, text: "Deep heading"))
    }
}
