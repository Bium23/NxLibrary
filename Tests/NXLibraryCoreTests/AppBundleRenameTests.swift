import XCTest
@testable import NXLibraryCore

final class AppBundleRenameTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("AppBundleRename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeBundle(_ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        return url
    }

    private func target(_ bundle: URL, isRelease: Bool = true, isTranslocated: Bool = false,
                        isBusy: Bool = false) -> URL? {
        AppBundleRename.target(bundleURL: bundle, isRelease: isRelease, isTranslocated: isTranslocated, isBusy: isBusy)
    }

    func testOldNameInWritableFolderBecomesArcane() throws {
        let bundle = try makeBundle("NX Library.app")
        let renamed = try XCTUnwrap(target(bundle))
        XCTAssertEqual(renamed.lastPathComponent, "Arcane.app")
        XCTAssertEqual(renamed.deletingLastPathComponent().standardizedFileURL, dir.standardizedFileURL)

        try AppBundleRename.perform(bundleURL: bundle, to: renamed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.appendingPathComponent("Contents").path))
    }

    func testExistingArcaneBlocksRename() throws {
        let bundle = try makeBundle("NX Library.app")
        try makeBundle("Arcane.app")
        XCTAssertNil(target(bundle))
    }

    func testReadOnlyFolderBlocksRename() throws {
        let bundle = try makeBundle("NX Library.app")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        XCTAssertNil(target(bundle))
    }

    func testDevelopmentCopyNeverRenames() throws {
        XCTAssertNil(target(try makeBundle("NX Library.app"), isRelease: false))
    }

    func testTranslocatedCopyNeverRenames() throws {
        XCTAssertNil(target(try makeBundle("NX Library.app"), isTranslocated: true))
    }

    func testBusyAppNeverRenames() throws {
        XCTAssertNil(target(try makeBundle("NX Library.app"), isBusy: true))
    }

    func testAnyOtherNameIsLeftAlone() throws {
        XCTAssertNil(target(try makeBundle("My Games.app")))
        XCTAssertNil(target(try makeBundle("Arcane.app")))
    }

    func testFailedMoveLeavesTheOldBundle() throws {
        let bundle = try makeBundle("NX Library.app")
        let renamed = try XCTUnwrap(target(bundle))
        try makeBundle("Arcane.app")
        XCTAssertThrowsError(try AppBundleRename.perform(bundleURL: bundle, to: renamed))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents").path))
    }
}
