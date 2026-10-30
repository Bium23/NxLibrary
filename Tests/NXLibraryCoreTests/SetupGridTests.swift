import XCTest
@testable import NXLibraryCore

final class SetupGridTests: XCTestCase {
    func testRowCounts() {
        XCTAssertEqual(SetupGrid.rowCounts(7), [4, 3])
        XCTAssertEqual(SetupGrid.rowCounts(11), [6, 5])
        XCTAssertEqual(SetupGrid.rowCounts(6), [6])
        XCTAssertEqual(SetupGrid.rowCounts(1), [1])
    }

    func testMove() {
        let rows = [4, 3]
        XCTAssertNil(SetupGrid.move(from: 3, .right, rowCounts: rows))
        XCTAssertEqual(SetupGrid.move(from: 2, .right, rowCounts: rows), 3)
        XCTAssertNil(SetupGrid.move(from: 4, .left, rowCounts: rows))
        XCTAssertEqual(SetupGrid.move(from: 0, .down, rowCounts: rows), 4)
        // Card 1 sits exactly between 4 and 5: going down picks the right one, going up the left one.
        XCTAssertEqual(SetupGrid.move(from: 1, .down, rowCounts: rows), 5)
        XCTAssertEqual(SetupGrid.move(from: 5, .up, rowCounts: rows), 1)
        XCTAssertNil(SetupGrid.move(from: 5, .down, rowCounts: rows))
        XCTAssertNil(SetupGrid.move(from: 0, .up, rowCounts: rows))
    }

    func testCentredOffsets() {
        XCTAssertEqual(SetupGrid.offset(of: 0, rowCounts: [4, 3]), -1.5)
        XCTAssertEqual(SetupGrid.offset(of: 5, rowCounts: [4, 3]), 0)
        XCTAssertEqual(SetupGrid.row(of: 4, rowCounts: [4, 3]), 1)
    }
}
