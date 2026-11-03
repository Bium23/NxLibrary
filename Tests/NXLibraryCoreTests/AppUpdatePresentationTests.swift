import XCTest
@testable import NXLibraryCore

final class AppUpdatePresentationTests: XCTestCase {
    func testCheckingReleasesDoesNotPermitReplacingDeveloperOrReadOnlyCopies() throws {
        let data = Data(#"{"tag_name":"v0.2.0","body":"Notes","assets":[{"name":"NXLibrary-0.2.0.zip","browser_download_url":"https://github.com/Bium23/NxLibrary/releases/download/v0.2.0/NXLibrary-0.2.0.zip","size":100,"digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}"#.utf8)
        let release = try XCTUnwrap(AppUpdate.parseRelease(data))
        XCTAssertFalse(AppUpdate.mayInstall(release, runningVersion: "0.1.0", installation: .developer))
        XCTAssertFalse(AppUpdate.mayInstall(release, runningVersion: "0.1.0", installation: .readOnly))
        XCTAssertTrue(AppUpdate.mayInstall(release, runningVersion: "0.1.0", installation: .ok))
        XCTAssertFalse(AppUpdate.mayInstall(release, runningVersion: "0.2.0", installation: .ok))
        XCTAssertFalse(AppUpdate.mayInstall(release, runningVersion: "0.3.0", installation: .ok))
    }
}
