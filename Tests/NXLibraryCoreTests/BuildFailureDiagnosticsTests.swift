import XCTest
@testable import NXLibraryCore

final class BuildFailureDiagnosticsTests: XCTestCase {
    func testProvisionalRewriteFailureNamesTheJumpTable() {
        let log = """
        {"ev": "say", "msg": "no game profile for 0100D1B006744000: reusing the provisional profile"}
        {"ev": "say", "msg": "[RED] patch_nso.py exit code 1 on main (full output: rewrite_main.log)"}
        {"ev": "say", "msg": "AssertionError: jump table 997b78"}
        """
        let message = BuildFailureDiagnostics.message(
            log: log, gameName: "Crash Bandicoot N Sane Trilogy",
            fallback: "Build exited with status 1"
        )
        XCTAssertTrue(message.contains("no verified nxnative game profile"))
        XCTAssertTrue(message.contains("0x997b78"))
        XCTAssertTrue(message.contains("not supported"))
        XCTAssertFalse(message.contains("Build exited with status 1"))
    }

    func testProvisionalFailureWithoutARewriteAddress() {
        let log = "provisional game profile: values guessed from the survey"
        let message = BuildFailureDiagnostics.message(
            log: log, gameName: "A Game", fallback: "Build exited with status 1"
        )
        XCTAssertTrue(message.contains("no verified nxnative game profile"))
        XCTAssertTrue(message.contains("may not be supported"))
    }

    func testNormalFailureKeepsTheFallback() {
        let message = BuildFailureDiagnostics.message(
            log: "Key import failed", gameName: "A Game",
            fallback: "Build exited with status 1"
        )
        XCTAssertEqual(message, "Build exited with status 1")
    }
}
