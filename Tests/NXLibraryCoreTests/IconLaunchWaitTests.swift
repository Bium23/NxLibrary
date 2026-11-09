import XCTest
@testable import NXLibraryCore

final class IconLaunchWaitTests: XCTestCase {
    func testOnlyTheRequestedGamesFinalSuccessfulUpdateMayLaunch() {
        let game = UUID(), notice = UUID()
        var wait = IconLaunchWait()
        wait.begin(gameID: game, noticeID: notice)
        XCTAssertNil(wait.finished(gameID: UUID(), rerun: false, succeeded: true, visibleNoticeID: notice))
        XCTAssertNil(wait.finished(gameID: game, rerun: true, succeeded: true, visibleNoticeID: notice))
        XCTAssertEqual(wait.finished(gameID: game, rerun: false, succeeded: true, visibleNoticeID: notice), game)
        XCTAssertNil(wait.gameID)
        XCTAssertNil(wait.finished(gameID: game, rerun: false, succeeded: true, visibleNoticeID: notice))
    }

    func testCancelPreventsLaunchingWhenSigningEventuallyEnds() {
        let game = UUID(), notice = UUID()
        var wait = IconLaunchWait()
        wait.begin(gameID: game, noticeID: notice)
        wait.cancel()
        XCTAssertNil(wait.finished(gameID: game, rerun: false, succeeded: true, visibleNoticeID: notice))
    }

    func testFailureOrDismissedNoticeDoesNotLaunch() {
        let game = UUID(), notice = UUID()
        var wait = IconLaunchWait()
        wait.begin(gameID: game, noticeID: notice)
        XCTAssertNil(wait.finished(gameID: game, rerun: false, succeeded: false, visibleNoticeID: notice))
        XCTAssertNil(wait.gameID)
        wait.begin(gameID: game, noticeID: notice)
        XCTAssertNil(wait.finished(gameID: game, rerun: false, succeeded: true, visibleNoticeID: UUID()))
        XCTAssertNil(wait.gameID)
    }
}
