import XCTest
@testable import NXLibraryCore

final class CursorIdleTests: XCTestCase {
    func testHidesAfterThreeSecondsAndMouseMovementRestartsTheDelay() {
        var cursor = CursorIdleState()
        XCTAssertFalse(cursor.update(now: 10, eligible: true))
        XCTAssertFalse(cursor.update(now: 12.9, eligible: true))
        XCTAssertTrue(cursor.update(now: 13, eligible: true))
        cursor.mouseActivity(now: 14)
        XCTAssertFalse(cursor.isHidden)
        XCTAssertFalse(cursor.update(now: 16.9, eligible: true))
        XCTAssertTrue(cursor.update(now: 17, eligible: true))
    }

    func testLeavingFullscreenOrOpeningADialogRestoresAndRestartsTheDelay() {
        var cursor = CursorIdleState()
        _ = cursor.update(now: 0, eligible: true)
        XCTAssertTrue(cursor.update(now: 3, eligible: true))
        XCTAssertFalse(cursor.update(now: 4, eligible: false))
        XCTAssertFalse(cursor.update(now: 20, eligible: true))
        XCTAssertFalse(cursor.update(now: 22.9, eligible: true))
        XCTAssertTrue(cursor.update(now: 23, eligible: true))
    }

    func testWindowedOrInactiveLauncherNeverHides() {
        var cursor = CursorIdleState()
        XCTAssertFalse(cursor.update(now: 0, eligible: false))
        XCTAssertFalse(cursor.update(now: 500, eligible: false))
        XCTAssertFalse(cursor.update(now: 501, eligible: true))
    }
}
