import XCTest
@testable import NXLibraryCore

final class MaterialIconTests: XCTestCase {
    func testSeleneCodepoints() {
        XCTAssertEqual(MaterialIcon.spotlight.rawValue, "\u{E3E0}")
        XCTAssertEqual(MaterialIcon.menu.rawValue, "\u{E5D2}")
        XCTAssertEqual(MaterialIcon.platform.rawValue, "\u{EA12}")
        XCTAssertEqual(MaterialIcon.trophy.rawValue, "\u{EA23}")
    }

    func testCodepointsAreSingleScalarsInPUA() {
        for icon in MaterialIcon.allCases {
            let scalars = icon.rawValue.unicodeScalars
            XCTAssertEqual(scalars.count, 1, "\(icon)")
            XCTAssertTrue((0xE000...0xF8FF).contains(scalars.first!.value), "\(icon)")
        }
    }

    func testNoDuplicateGlyphs() {
        let all = MaterialIcon.allCases.map(\.rawValue)
        XCTAssertEqual(Set(all).count, all.count)
    }
}
