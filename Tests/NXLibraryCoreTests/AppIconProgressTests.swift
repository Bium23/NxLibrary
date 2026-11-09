import XCTest
@testable import NXLibraryCore

final class AppIconProgressTests: XCTestCase {
    func testMissingIconAddsAnInformationalResultWithoutReplacingBuildOutput() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let log = folder.appendingPathComponent("build.log")
        try Data("engine: build completed\n".utf8).write(to: log)
        try AppIconProgress.unavailable.appendToBuildLog(log)
        let text = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("engine: build completed\n"))
        XCTAssertTrue(text.contains("Game ready. No icon found"))
        XCTAssertFalse(text.lowercased().contains("build failed"))
    }
}
