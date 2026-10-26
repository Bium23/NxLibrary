import XCTest
@testable import NXLibraryCore

final class BuildOutputInstallerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXInstall-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func makeApp(_ name: String, marker: String) throws -> URL {
        let app = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try marker.write(to: app.appendingPathComponent("Contents/Info.plist"),
                         atomically: true, encoding: .utf8)
        return app
    }

    func testReplacesOldApp() throws {
        let temp = try makeApp("Temp.app", marker: "new")
        let final = try makeApp("Final.app", marker: "old")
        try BuildOutputInstaller.install(tempApp: temp, finalApp: final)
        XCTAssertEqual(try String(contentsOf: final.appendingPathComponent("Contents/Info.plist")),
                       "new")
    }

    func testInvalidTempPreservesOldApp() throws {
        let temp = root.appendingPathComponent("Broken.app")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let final = try makeApp("Final.app", marker: "old")
        XCTAssertThrowsError(try BuildOutputInstaller.install(tempApp: temp, finalApp: final))
        XCTAssertEqual(try String(contentsOf: final.appendingPathComponent("Contents/Info.plist")),
                       "old")
    }

    func testRefusesToReplaceANonAppItem() throws {
        let temp = try makeApp("Temp.app", marker: "new")
        let final = root.appendingPathComponent("Final.app")
        try FileManager.default.createDirectory(at: final, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: final.appendingPathComponent("source.nsp"))
        XCTAssertThrowsError(try BuildOutputInstaller.install(tempApp: temp, finalApp: final))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: final.appendingPathComponent("source.nsp").path))
        XCTAssertEqual(try String(contentsOf: temp.appendingPathComponent("Contents/Info.plist")),
                       "new")
    }
}
