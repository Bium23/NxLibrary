import XCTest
@testable import NXLibraryCore

final class PixelGridTests: XCTestCase {
    func testAlignsOriginAndSizeToWholeBackingPixels() {
        // 60.8 pt at 2x is 121.6 px; the origin 10.3/20.7 pt is 20.6/41.4 px.
        let rect = PixelGrid.align(CGRect(x: 10.3, y: 20.7, width: 60.8, height: 60.8), scale: 2)
        XCTAssertEqual(rect.origin.x, 10.5, accuracy: 1e-9)
        XCTAssertEqual(rect.origin.y, 20.5, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 61, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 61, accuracy: 1e-9)
    }

    func testAlreadyAlignedRectIsUnchanged() {
        let rect = CGRect(x: 4, y: 7.5, width: 76, height: 76)
        XCTAssertEqual(PixelGrid.align(rect, scale: 2), rect)
    }

    func testOneTimesScaleAndInvalidScale() {
        XCTAssertEqual(PixelGrid.align(CGRect(x: 0.4, y: 0.6, width: 10.5, height: 10.4), scale: 1),
                       CGRect(x: 0, y: 1, width: 11, height: 10))
        let rect = CGRect(x: 0.4, y: 0.6, width: 10.5, height: 10.4)
        XCTAssertEqual(PixelGrid.align(rect, scale: 0), rect)
    }
}
