import XCTest
@testable import NXLibraryCore

final class SeleneLayoutMetricsTests: XCTestCase {
    func testMetricsAt1600() {
        let m = SeleneLayoutMetrics(width: 1600)
        XCTAssertEqual(m.margin, 64)
        XCTAssertEqual(m.sidebarWidth, 248)
        XCTAssertEqual(m.heroTitleSize, 72, accuracy: 0.001)
        XCTAssertEqual(m.railCardWidth, 128)
        XCTAssertEqual(m.railCardHeight, 171)
        XCTAssertEqual(m.contentWidth, 1472)
        XCTAssertFalse(m.isCompact)
    }

    func testMetricsAt1440() {
        let m = SeleneLayoutMetrics(width: 1440)
        XCTAssertEqual(m.margin, 48)
        XCTAssertEqual(m.sidebarWidth, 220)
        XCTAssertEqual(m.heroTitleSize, 64.8, accuracy: 0.001)
        XCTAssertEqual(m.railCardWidth, 112)
        XCTAssertEqual(m.railCardHeight, 149)
        XCTAssertEqual(m.contentWidth, 1344)
        XCTAssertFalse(m.isCompact)
    }

    func testMetricsAt1100() {
        let m = SeleneLayoutMetrics(width: 1100)
        XCTAssertEqual(m.margin, 32)
        XCTAssertEqual(m.sidebarWidth, 220)
        XCTAssertEqual(m.heroTitleSize, 49.5, accuracy: 0.001)
        XCTAssertEqual(m.railCardWidth, 112)
        XCTAssertEqual(m.railCardHeight, 149)
        XCTAssertEqual(m.contentWidth, 1036)
        XCTAssertTrue(m.isCompact)
    }

    func testNegativeWidthIsClamped() {
        let m = SeleneLayoutMetrics(width: -20)
        XCTAssertEqual(m.margin, 32)
        XCTAssertEqual(m.contentWidth, 0)
    }
}
