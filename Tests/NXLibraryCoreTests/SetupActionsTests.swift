import XCTest
@testable import NXLibraryCore

final class SetupActionsTests: XCTestCase {
    private let pin = "af616f54652fa7f50a2e223ceed1d08a9bc83848"

    func testEngineAction() {
        XCTAssertEqual(SetupActions.engineAction(for: .missing, pinned: pin), .clone)
        XCTAssertEqual(SetupActions.engineAction(for: .checkout(head: "ee369f0", dirty: false), pinned: pin), .checkout)
        XCTAssertEqual(SetupActions.engineAction(for: .checkout(head: "ee369f0", dirty: true), pinned: pin), .none)
        XCTAssertEqual(SetupActions.engineAction(for: .checkout(head: pin, dirty: false), pinned: pin), .none)
        XCTAssertEqual(SetupActions.engineAction(for: .notACheckout, pinned: pin), .none)
    }

    func testCloneArgv() {
        let folder = URL(fileURLWithPath: "/Users/a b/nx native")
        XCTAssertEqual(SetupActions.gitCommands(for: .clone, folder: folder, pinned: pin), [
            ["clone", SetupActions.engineRemote, "/Users/a b/nx native"],
            ["-C", "/Users/a b/nx native", "checkout", "--detach", pin],
        ])
        XCTAssertEqual(SetupActions.engineRemote, "https://github.com/seedds/nxnative")
    }

    func testCheckoutArgv() {
        let folder = URL(fileURLWithPath: "/Users/me/nxnative")
        XCTAssertEqual(SetupActions.gitCommands(for: .checkout, folder: folder, pinned: pin), [
            ["-C", "/Users/me/nxnative", "fetch", "origin"],
            ["-C", "/Users/me/nxnative", "checkout", "--detach", pin],
        ])
        XCTAssertEqual(SetupActions.gitCommands(for: .none, folder: folder, pinned: pin), [])
        XCTAssertEqual(SetupActions.metalDownload, ["-downloadComponent", "MetalToolchain"])
    }
}
