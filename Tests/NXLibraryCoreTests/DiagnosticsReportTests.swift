import XCTest
@testable import NXLibraryCore

final class DiagnosticsReportTests: XCTestCase {
    private func inputs() -> DiagnosticsReport.Inputs {
        var i = DiagnosticsReport.Inputs()
        i.appVersion = "1.0"
        i.bundleID = "local.nxlibrary"
        i.macOS = "27.2"
        i.chip = "Apple M4"
        i.pinnedCommit = "ee369f09984f23adbe003f55e94be5d81cd8c0e6"
        i.engineHead = "ee369f0 fix: something"
        i.home = "/Users/someone"
        i.xcodePath = "/Applications/Xcode.app/Contents/Developer"
        i.setupRows = [("Xcode", true), (".NET SDK", false)]
        i.keysImported = true
        i.hasHeaderKey = true
        i.keyGenerations = 19
        i.lastCommand = ["/Users/someone/nxnative/.venv/bin/python3", "build_ipa_from_nsp.py"]
        i.log = ["one", "two"]
        return i
    }

    func testHomeBecomesTilde() {
        XCTAssertEqual(DiagnosticsReport.scrub("/Users/someone/nxnative/x.log", home: "/Users/someone"), "~/nxnative/x.log")
        let report = DiagnosticsReport.markdown(inputs())
        XCTAssertFalse(report.contains("/Users/someone"))
        XCTAssertTrue(report.contains("~/nxnative/.venv/bin/python3"))
    }

    func testKeyLikeLinesAreRedacted() {
        let hex = String(repeating: "ab", count: 16)
        XCTAssertEqual(DiagnosticsReport.scrub("header_key = \(hex)\(hex)", home: "/h"), "header_key = <redacted>")
        let inline = DiagnosticsReport.scrub("loaded title_key = \(hex) for 0100", home: "/h")
        XCTAssertFalse(inline.contains(hex))
        XCTAssertTrue(inline.contains("title_key = <redacted>"))
        var i = inputs()
        i.log = ["  master_key_00 = \(hex)"]
        XCTAssertFalse(DiagnosticsReport.markdown(i).contains(hex))
    }

    func testDiagnosticsCheatsLineHasNoNames() {
        var i = inputs()
        i.game = (name: "Game", titleID: "0100000000010000", built: true, toolchainVerified: true, failure: nil)
        i.cheats = (buildID: "B424BE150A8E7D78", filePresent: true, total: 12, on: 3, broken: 2, masterOn: true, safeMode: false)
        let report = DiagnosticsReport.markdown(i)
        XCTAssertTrue(report.contains("- Cheats: build B424BE150A8E7D78, file yes, 12 cheats, 3 on, 2 not supported, master on, safe mode no"), report)
        XCTAssertFalse(report.contains("SECRET"))
        i.cheats = nil
        XCTAssertTrue(DiagnosticsReport.markdown(i).contains("- Cheats: —"))
    }

    func testReportHasSections() {
        var i = inputs()
        i.game = ("A Game", "0100000000010000", false, nil, "noProfile")
        let report = DiagnosticsReport.markdown(i)
        for heading in ["## App", "## Engine", "## Toolchain", "## Setup", "## Keys", "## Selected game", "## Last porting"] {
            XCTAssertTrue(report.contains(heading), heading)
        }
        XCTAssertTrue(report.contains("noProfile"))
        XCTAssertTrue(report.contains(".NET SDK: missing"))
    }

    func testNoGameSectionWithoutGame() {
        XCTAssertFalse(DiagnosticsReport.markdown(inputs()).contains("## Selected game"))
    }

    func testLogIsLast50Lines() {
        var i = inputs()
        i.log = (1...80).map { "line \($0)" }
        let report = DiagnosticsReport.markdown(i)
        XCTAssertFalse(report.contains("line 30\n"))
        XCTAssertTrue(report.contains("line 31\n"))
        XCTAssertTrue(report.contains("line 80"))
    }
}
