import XCTest
@testable import NXLibraryCore

final class HoldDetectorTests: XCTestCase {
    func testQuickReleaseIsTap() {
        var d = HoldDetector()
        d.press(at: 0)
        XCTAssertEqual(d.release(at: 0.2), .tap)
    }

    func testTickPastThresholdIsHoldOnce() {
        var d = HoldDetector()
        d.press(at: 0)
        XCTAssertEqual(d.tick(at: 0.6), .hold)
        XCTAssertNil(d.tick(at: 0.7))
        XCTAssertNil(d.release(at: 0.8))
    }

    func testReleaseExactlyAtThresholdIsHold() {
        var d = HoldDetector()
        d.press(at: 0)
        XCTAssertEqual(d.release(at: 0.5), .hold)
    }

    func testReleaseWithoutPressIsNil() {
        var d = HoldDetector()
        XCTAssertNil(d.release(at: 1))
        XCTAssertNil(d.tick(at: 1))
    }
}
