import XCTest
@testable import NXLibraryCore

final class ListScrollBandTests: XCTestCase {
    func testRowInsideTheBandDoesNotScroll() {
        XCTAssertNil(ListScrollBand.anchor(rowTop: 100, rowHeight: 100, viewport: 1000, safeTop: 40, safeBottom: 870))
    }

    func testRowAboveTheBandLandsOnItsTop() {
        let anchor = ListScrollBand.anchor(rowTop: 10, rowHeight: 100, viewport: 1000, safeTop: 40, safeBottom: 870)
        XCTAssertEqual(anchor!, 40.0 / 900, accuracy: 1e-9)
    }

    func testRowBelowTheBandLandsOnItsBottom() {
        let anchor = ListScrollBand.anchor(rowTop: 800, rowHeight: 100, viewport: 1000, safeTop: 40, safeBottom: 870)
        XCTAssertEqual(anchor!, 770.0 / 900, accuracy: 1e-9)
    }

    func testViewportNoTallerThanARowAnchorsAtTheTop() {
        XCTAssertEqual(ListScrollBand.anchor(rowTop: 500, rowHeight: 100, viewport: 80, safeTop: 40, safeBottom: 60), 0)
    }
}
