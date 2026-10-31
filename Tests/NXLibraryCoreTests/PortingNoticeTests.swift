import XCTest
@testable import NXLibraryCore

final class PortingNoticeTests: XCTestCase {
    func testNoNoticeWhenActive() {
        XCTAssertFalse(PortingNotice.shouldNotify(success: true, cancelled: false, enabled: true, appActive: true))
        XCTAssertTrue(PortingNotice.shouldNotify(success: true, cancelled: false, enabled: true, appActive: false))
        XCTAssertTrue(PortingNotice.shouldNotify(success: false, cancelled: false, enabled: true, appActive: false))
    }

    func testNoNoticeWhenCancelled() {
        XCTAssertFalse(PortingNotice.shouldNotify(success: false, cancelled: true, enabled: true, appActive: false))
    }

    func testNoNoticeWhenOff() {
        XCTAssertFalse(PortingNotice.shouldNotify(success: true, cancelled: false, enabled: false, appActive: false))
    }

    func testSuccessText() {
        let text = PortingNotice.text(game: "A Game", success: true, reason: nil)
        XCTAssertEqual(text.title, "A Game is ready")
        XCTAssertEqual(text.body, "Play it from your library.")
    }

    func testHeldText() {
        let text = PortingNotice.text(game: "A Game", success: true, reason: nil, held: true)
        XCTAssertEqual(text.title, "A Game is ready")
        XCTAssertEqual(text.body, "It installs when you quit the game.")
    }

    func testFailureBodyIsReasonTitle() {
        let reason = PortingFailureReason(kind: .keysTooOld, detail: "19.0.0")
        let text = PortingNotice.text(game: "A Game", success: false, reason: reason)
        XCTAssertEqual(text.title, "A Game did not port")
        XCTAssertEqual(text.body, reason.title)
        XCTAssertEqual(PortingNotice.text(game: "A Game", success: false, reason: nil).body,
                       PortingFailureReason(kind: .unknown).title)
    }
}
