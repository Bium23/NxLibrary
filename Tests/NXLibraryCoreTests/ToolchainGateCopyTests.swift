import XCTest
@testable import NXLibraryCore

final class ToolchainGateCopyTests: XCTestCase {
    private func report(metal: MetalStanding, otherBlock: Bool = false) -> CompatibilityReport {
        var checks = [CompatibilityCheck(id: "metal", title: "Metal compiler",
                                         status: metal == .same ? .pass : .block, detail: "")]
        if otherBlock { checks.append(.init(id: "tree", title: "Working tree", status: .block, detail: "")) }
        return CompatibilityReport(ok: checks.allSatisfy { $0.status != .block }, checks: checks, metal: metal)
    }

    private let newer = MetalStanding.newer(installed: "32023.922", required: "32023.921")
    private let older = MetalStanding.older(installed: "32023.917", required: "32023.921")

    func testCertified() {
        let s = ToolchainGateCopy.summary(report: report(metal: .same), overrideOn: false)
        XCTAssertEqual(s.label, "Certified")
        XCTAssertEqual(s.tone, .certified)
        XCTAssertNil(s.message)
    }

    func testNewerMetalIsInformationNotBlocked() {
        let off = ToolchainGateCopy.summary(report: report(metal: newer), overrideOn: false)
        XCTAssertEqual(off.label, "Newer Metal")
        XCTAssertEqual(off.tone, .info)
        XCTAssertEqual(off.message, "Your Metal compiler (32023.922) is newer than the one nxnative is tested with (32023.921). There should be no problems: turn on Untested toolchain override to build.")
        XCTAssertEqual(off.buildHint, "Newer Metal: turn on the override in Settings → Engine")
        let on = ToolchainGateCopy.summary(report: report(metal: newer), overrideOn: true)
        XCTAssertEqual(on.label, "Newer Metal · override on")
        XCTAssertEqual(on.tone, .info)
        XCTAssertEqual(on.message, "Your Metal compiler (32023.922) is newer than the one nxnative is tested with (32023.921). There should be no problems; builds are recorded as untested.")
    }

    func testOlderMetalRecommendsUpdating() {
        let off = ToolchainGateCopy.summary(report: report(metal: older), overrideOn: false)
        XCTAssertEqual(off.label, "Update recommended")
        XCTAssertEqual(off.tone, .warning)
        XCTAssertEqual(off.message, "Your Metal compiler (32023.917) is older than the one nxnative needs (32023.921). Updating to Metal 32023.921 is strongly recommended. Untested toolchain override builds anyway, at your own risk.")
        XCTAssertEqual(off.buildHint, "Older Metal: update it, or use the override in Settings → Engine")
        let on = ToolchainGateCopy.summary(report: report(metal: older), overrideOn: true)
        XCTAssertEqual(on.label, "Older Metal · override on")
        XCTAssertEqual(on.tone, .warning)
    }

    func testOtherProblemsStayBlocked() {
        let s = ToolchainGateCopy.summary(report: report(metal: newer, otherBlock: true), overrideOn: false)
        XCTAssertEqual(s.label, "Blocked")
        XCTAssertEqual(s.tone, .blocked)
        XCTAssertEqual(s.buildHint, "Build blocked — Settings → Engine")
        let on = ToolchainGateCopy.summary(report: report(metal: .same, otherBlock: true), overrideOn: true)
        XCTAssertEqual(on.label, "Override enabled")
        XCTAssertEqual(on.tone, .override)
        XCTAssertEqual(ToolchainGateCopy.summary(report: report(metal: .unknown), overrideOn: false).tone, .blocked)
    }
}
