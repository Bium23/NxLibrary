import XCTest
@testable import NXLibraryCore

final class SmokeTests: XCTestCase {
    func testCoreVersion() {
        XCTAssertEqual(NXLibraryCore.version, "0.1.0")
    }
}
