import XCTest
@testable import NXLibraryCore

final class ArtworkPickerFocusTests: XCTestCase {
    // 8 tiles in rows of 3: 0 1 2 / 3 4 5 / 6 7
    func testSidewaysClampsAtTheEnds() {
        XCTAssertEqual(ArtworkPickerFocus.moved(0, by: .left, count: 8, columns: 3), 0)
        XCTAssertEqual(ArtworkPickerFocus.moved(0, by: .right, count: 8, columns: 3), 1)
        XCTAssertEqual(ArtworkPickerFocus.moved(7, by: .right, count: 8, columns: 3), 7)
    }

    func testVerticalMovesByRowAndLandsOnAShortLastRow() {
        XCTAssertEqual(ArtworkPickerFocus.moved(1, by: .down, count: 8, columns: 3), 4)
        XCTAssertEqual(ArtworkPickerFocus.moved(5, by: .down, count: 8, columns: 3), 7, "short last row: its last tile")
        XCTAssertEqual(ArtworkPickerFocus.moved(7, by: .down, count: 8, columns: 3), 7)
        XCTAssertEqual(ArtworkPickerFocus.moved(4, by: .up, count: 8, columns: 3), 1)
        XCTAssertEqual(ArtworkPickerFocus.moved(1, by: .up, count: 8, columns: 3), 1)
        XCTAssertEqual(ArtworkPickerFocus.moved(0, by: .down, count: 0, columns: 3), 0)
    }

    func testSlotsCycle() {
        XCTAssertEqual(ArtworkPickerFocus.slot(after: .cover, by: 1), .background)
        XCTAssertEqual(ArtworkPickerFocus.slot(after: .logo, by: 1), .logo, "the tabs do not wrap")
        XCTAssertEqual(ArtworkPickerFocus.slot(after: .cover, by: -1), .cover)
    }
}
