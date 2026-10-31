import XCTest
@testable import NXLibraryCore

final class EngineLocationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("NXEngine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func makeEngine(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("dm"), withIntermediateDirectories: true)
        try Data().write(to: url.appendingPathComponent("scripts/build_ipa_from_nsp.py"))
    }

    func testDefaultIsNxnativeInHome() {
        XCTAssertEqual(EngineLocation.folder(saved: nil, home: root).path, root.appendingPathComponent("nxnative").path)
        XCTAssertEqual(EngineLocation.folder(saved: "", home: root).path, root.appendingPathComponent("nxnative").path)
    }

    func testAChosenFolderIsUsedWhileItExists() throws {
        let chosen = root.appendingPathComponent("Code/nxnative-fork")
        try makeEngine(chosen)
        XCTAssertEqual(EngineLocation.folder(saved: chosen.path, home: root).path, chosen.path)
    }

    func testAChosenFolderThatIsGoneFallsBackToTheDefault() {
        let gone = root.appendingPathComponent("Volumes/SSD/nxnative").path
        XCTAssertEqual(EngineLocation.folder(saved: gone, home: root).path, root.appendingPathComponent("nxnative").path)
    }

    func testIsEngineNeedsTheBuildScriptAndDm() throws {
        let folder = root.appendingPathComponent("maybe")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertFalse(EngineLocation.isEngine(folder))
        try makeEngine(folder)
        XCTAssertTrue(EngineLocation.isEngine(folder))
    }

    func testSavedValueIsNilForTheDefaultFolder() throws {
        XCTAssertNil(EngineLocation.savedValue(for: root.appendingPathComponent("nxnative/"), home: root))
        let other = root.appendingPathComponent("Code/nxnative")
        XCTAssertEqual(EngineLocation.savedValue(for: other, home: root), other.standardizedFileURL.path)
    }
}
