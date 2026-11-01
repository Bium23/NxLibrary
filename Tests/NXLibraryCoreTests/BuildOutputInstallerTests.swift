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

    func testCompletedInstallCanBeRetriedAfterItsSourceWasCleanedUp() throws {
        let temp = try makeApp("Temp.app", marker: "new")
        let final = try makeApp("Final.app", marker: "old")
        try BuildOutputInstaller.install(tempApp: temp, finalApp: final)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
        XCTAssertNoThrow(try BuildOutputInstaller.install(tempApp: temp, finalApp: final))
        XCTAssertEqual(try String(contentsOf: final.appendingPathComponent("Contents/Info.plist")), "new")
    }

    func testAnInterruptedReplacementKeepsAnAppAtTheFinalPath() throws {
        let temp = try makeApp("Temp.app", marker: "new")
        let final = try makeApp("Final.app", marker: "old")
        let fm = InterruptAfterMovingCurrentApp(current: final)
        _ = try? BuildOutputInstaller.install(tempApp: temp, finalApp: final, fileManager: fm)
        XCTAssertTrue(FileManager.default.fileExists(atPath: final.appendingPathComponent("Contents/Info.plist").path))
    }

    private func marker(_ app: URL) throws -> String {
        try String(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
    }

    private func incomingApps() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".nxlibrary-incoming-") }
    }

    func testFailureBeforePublicationPreservesBothAppsAndCanBeRetried() throws {
        let temp = try makeApp("Temp.app", marker: "new")
        let final = try makeApp("Final.app", marker: "old")
        var io = BuildInstallIO()
        io.publish = { _, _, _ in throw CocoaError(.fileWriteNoPermission) }
        XCTAssertThrowsError(try BuildOutputInstaller.install(tempApp: temp, finalApp: final, io: io))
        XCTAssertEqual(try marker(final), "old")
        XCTAssertEqual(try marker(temp), "new")
        try BuildOutputInstaller.install(tempApp: temp, finalApp: final)
        XCTAssertEqual(try marker(final), "new")
        XCTAssertTrue(try incomingApps().isEmpty, "same-volume installs do not copy the app")
    }

    func testInterruptionAfterPublicationNeverSwapsTheOldAppBack() throws {
        let temp = try makeApp("Temp.app", marker: "new")
        let final = try makeApp("Final.app", marker: "old")
        var io = BuildInstallIO()
        io.afterPublish = { throw CocoaError(.userCancelled) }
        XCTAssertThrowsError(try BuildOutputInstaller.install(tempApp: temp, finalApp: final, io: io))
        XCTAssertEqual(try marker(final), "new")
        XCTAssertEqual(try marker(temp), "old", "the old app is still available before cleanup")
        try BuildOutputInstaller.install(tempApp: temp, finalApp: final)
        try BuildOutputInstaller.install(tempApp: temp, finalApp: final)
        XCTAssertEqual(try marker(final), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
    }

    func testFirstInstallAndRetryAfterInterruption() throws {
        let temp = try makeApp("Temp.app", marker: "first")
        let final = root.appendingPathComponent("Applications/Final.app")
        var io = BuildInstallIO()
        io.afterPublish = { throw CocoaError(.userCancelled) }
        XCTAssertThrowsError(try BuildOutputInstaller.install(tempApp: temp, finalApp: final, io: io))
        XCTAssertEqual(try marker(final), "first")
        try BuildOutputInstaller.install(tempApp: temp, finalApp: final)
        XCTAssertEqual(try marker(final), "first")
    }

    func testFirstInstallDoesNotOverwriteAnAppThatAppearsBeforePublication() throws {
        let temp = try makeApp("Temp.app", marker: "new")
        let final = root.appendingPathComponent("Final.app")
        var io = BuildInstallIO()
        let publish = io.publish
        io.publish = { source, destination, replacing in
            _ = try self.makeApp("Final.app", marker: "external")
            try publish(source, destination, replacing)
        }
        XCTAssertThrowsError(try BuildOutputInstaller.install(tempApp: temp, finalApp: final, io: io))
        XCTAssertEqual(try marker(final), "external")
        XCTAssertEqual(try marker(temp), "new")
        XCTAssertThrowsError(try BuildOutputInstaller.install(tempApp: temp, finalApp: final))
        XCTAssertEqual(try marker(final), "external", "a retry must not overwrite an unrelated change")
        try FileManager.default.removeItem(at: final)
        try BuildOutputInstaller.install(tempApp: temp, finalApp: final)
        XCTAssertEqual(try marker(final), "new")
    }

    func testCrossVolumePreparationSurvivesPublicationFailure() throws {
        let temp = try makeApp("Temp.app", marker: "new")
        let final = try makeApp("Final.app", marker: "old")
        var io = BuildInstallIO()
        io.sameVolume = { _, _ in false }
        io.publish = { _, _, _ in throw CocoaError(.fileWriteNoPermission) }
        XCTAssertThrowsError(try BuildOutputInstaller.install(tempApp: temp, finalApp: final, io: io))
        XCTAssertEqual(try marker(final), "old")
        XCTAssertEqual(try marker(temp), "new")
        let copy = try XCTUnwrap(try incomingApps().first)
        XCTAssertEqual(try marker(copy), "new")
        try BuildOutputInstaller.install(tempApp: temp, finalApp: final)
        XCTAssertEqual(try marker(final), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
        XCTAssertTrue(try incomingApps().isEmpty)
    }

    func testCrossVolumeCopyFailurePreservesBothAppsAndCanBeRetried() throws {
        let temp = try makeApp("Temp.app", marker: "new")
        let final = try makeApp("Final.app", marker: "old")
        var io = BuildInstallIO()
        io.sameVolume = { _, _ in false }
        XCTAssertThrowsError(try BuildOutputInstaller.install(tempApp: temp, finalApp: final,
                                                              fileManager: FailDuringCopy(), io: io))
        XCTAssertEqual(try marker(final), "old")
        XCTAssertEqual(try marker(temp), "new")
        XCTAssertTrue(try incomingApps().isEmpty, "partial copies are not left as prepared apps")
        try BuildOutputInstaller.install(tempApp: temp, finalApp: final, io: io)
        XCTAssertEqual(try marker(final), "new")
        XCTAssertTrue(try incomingApps().isEmpty)
    }

    func testCrossVolumeInterruptionAfterPublicationCanBeRetried() throws {
        let temp = try makeApp("Temp.app", marker: "new")
        let final = try makeApp("Final.app", marker: "old")
        var io = BuildInstallIO()
        io.sameVolume = { _, _ in false }
        io.afterPublish = { throw CocoaError(.userCancelled) }
        XCTAssertThrowsError(try BuildOutputInstaller.install(tempApp: temp, finalApp: final, io: io))
        XCTAssertEqual(try marker(final), "new")
        XCTAssertEqual(try marker(temp), "new", "the source is retained until publication is acknowledged")
        XCTAssertEqual(try marker(try XCTUnwrap(try incomingApps().first)), "old")
        try BuildOutputInstaller.install(tempApp: temp, finalApp: final)
        XCTAssertEqual(try marker(final), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
        XCTAssertTrue(try incomingApps().isEmpty)
    }

    func testNextBuildToTheSameDestinationStartsANewInstallation() throws {
        let first = try makeApp("First.app", marker: "first")
        let final = try makeApp("Final.app", marker: "old")
        try BuildOutputInstaller.install(tempApp: first, finalApp: final)
        let second = try makeApp("Second.app", marker: "second")
        try BuildOutputInstaller.install(tempApp: second, finalApp: final)
        try BuildOutputInstaller.install(tempApp: second, finalApp: final)
        XCTAssertEqual(try marker(final), "second")
    }

    func testRejectsOverlappingAppPaths() throws {
        let final = try makeApp("Final.app", marker: "old")
        XCTAssertThrowsError(try BuildOutputInstaller.install(tempApp: final, finalApp: final))
        let nested = try makeApp("Final.app/Nested.app", marker: "new")
        XCTAssertThrowsError(try BuildOutputInstaller.install(tempApp: nested, finalApp: final))
        XCTAssertThrowsError(try BuildOutputInstaller.install(tempApp: final, finalApp: nested))
        XCTAssertEqual(try marker(final), "old")
        XCTAssertEqual(try marker(nested), "new")
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

private final class InterruptAfterMovingCurrentApp: FileManager, @unchecked Sendable {
    let current: URL
    init(current: URL) { self.current = current; super.init() }

    override func moveItem(at source: URL, to destination: URL) throws {
        try super.moveItem(at: source, to: destination)
        if source == current { throw CocoaError(.userCancelled) }
    }
}

private final class FailDuringCopy: FileManager, @unchecked Sendable {
    override func copyItem(at source: URL, to destination: URL) throws {
        try createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: destination.appendingPathComponent("partial"))
        throw CocoaError(.fileWriteOutOfSpace)
    }
}
