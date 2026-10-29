import XCTest
import CoreGraphics
@testable import NXLibraryCore

final class SeleneCanvasTests: XCTestCase {
    func testScaleIsMinOfAxes() {
        XCTAssertEqual(SeleneCanvas(size: CGSize(width: 1920, height: 1080)).scale, 1)
        XCTAssertEqual(SeleneCanvas(size: CGSize(width: 1440, height: 900)).scale, 0.75)
        XCTAssertEqual(SeleneCanvas(size: CGSize(width: 3440, height: 1440)).scale, 1440.0 / 1080.0, accuracy: 0.0001)
    }

    func testUnitsScale() {
        XCTAssertEqual(SeleneCanvas(size: CGSize(width: 1440, height: 900)).u(19), 14.25, accuracy: 0.0001)
    }

    func testStageIsCentered16by9() {
        let c = SeleneCanvas(size: CGSize(width: 3440, height: 1440))
        XCTAssertEqual(c.stageSize.width, 2560, accuracy: 0.01)
        XCTAssertEqual(c.stageSize.height, 1440, accuracy: 0.01)
        XCTAssertEqual(c.stageOrigin.x, 440, accuracy: 0.01)
        XCTAssertEqual(c.stageOrigin.y, 0, accuracy: 0.01)
    }

    func testMinimumWindowAndZero() {
        XCTAssertEqual(SeleneCanvas(size: CGSize(width: 1100, height: 700)).scale, 1100.0 / 1920.0, accuracy: 0.0001)
        XCTAssertEqual(SeleneCanvas(size: .zero).scale, 0)
    }
}
