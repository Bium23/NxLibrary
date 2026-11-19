import XCTest
@testable import NXLibraryCore

/// `waitUntilExit` runs the current run loop while it waits: a SwiftUI update that started a command (Game options
/// reading the engine's ancestry for its Cheats row) re-entered itself and aborted.
final class SystemCommandRunnerTests: XCTestCase {
    private let sleep = URL(fileURLWithPath: "/bin/sleep")

    func testRunWaitsWithoutRunningTheRunLoop() throws {
        var ran = false
        RunLoop.current.perform { ran = true }
        let result = try SystemCommandRunner().run(sleep, ["0.2"], environment: nil, currentDirectory: nil)
        XCTAssertEqual(result.status, 0)
        XCTAssertFalse(ran, "Work queued on the run loop ran while the command was awaited")
        RunLoop.current.run(until: Date())
    }

    func testStreamWaitsWithoutRunningTheRunLoop() throws {
        var ran = false
        RunLoop.current.perform { ran = true }
        let result = try SystemCommandRunner().stream(sleep, ["0.2"], environment: nil, currentDirectory: nil) { _ in }
        XCTAssertEqual(result.status, 0)
        XCTAssertFalse(ran, "Work queued on the run loop ran while the command was awaited")
        RunLoop.current.run(until: Date())
    }
}
