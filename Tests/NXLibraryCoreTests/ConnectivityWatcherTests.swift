import XCTest
@testable import NXLibraryCore

final class ConnectivityWatcherTests: XCTestCase {
    func testOnlyOfflineToOnlineIsAReturn() {
        XCTAssertTrue(ConnectivityWatcher.returned(previous: false, current: true))
        XCTAssertFalse(ConnectivityWatcher.returned(previous: nil, current: true), "the first reading is not a return")
        XCTAssertFalse(ConnectivityWatcher.returned(previous: true, current: true))
        XCTAssertFalse(ConnectivityWatcher.returned(previous: true, current: false))
        XCTAssertFalse(ConnectivityWatcher.returned(previous: false, current: false))
    }
}
