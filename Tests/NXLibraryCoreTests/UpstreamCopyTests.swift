import XCTest
@testable import NXLibraryCore

final class UpstreamCopyTests: XCTestCase {
    func testNewCommitsArriveWithUpdates() {
        XCTAssertEqual(UpstreamCopy.subtitle(upToDate: true, newCommits: 0), "This NX Library uses the newest nxnative.")
        XCTAssertEqual(UpstreamCopy.subtitle(upToDate: false, newCommits: 1),
                       "nxnative has 1 newer commit. Engine updates reach you with NX Library updates, once tested.")
        XCTAssertEqual(UpstreamCopy.subtitle(upToDate: false, newCommits: 12),
                       "nxnative has 12 newer commits. Engine updates reach you with NX Library updates, once tested.")
    }
}
