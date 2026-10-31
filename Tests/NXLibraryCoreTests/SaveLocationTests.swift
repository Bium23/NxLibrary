import XCTest
import Darwin
@testable import NXLibraryCore

final class SaveLocationTests: XCTestCase {
    func testOwnCloudPreferenceBlocksDespiteLibraryOff() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        XCTAssertThrowsError(try SaveLocation.resolve(titleID: h.tid, appURL: h.app,
            home: h.home, environment: [:], gameCloudFolder: "/cloud", libraryCloudFolder: nil))
        let context = try SaveLocation.inspect(titleID: h.tid, appURL: h.app,
            home: h.home, environment: [:], gameCloudFolder: "/cloud", libraryCloudFolder: nil)
        XCTAssertNotNil(context.cloudReason)
    }
    func testIDsAndDefaultPath() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        for id in ["..", "010000000000000G", "０10000000000001", " 0100000000000001", ""] {
            XCTAssertThrowsError(try h.location(id: id))
        }
        XCTAssertEqual(try h.location(id: "01000000000000ab").titleID, "01000000000000AB")
        XCTAssertEqual(try h.location().directory(.device).lastPathComponent, "save_device")
    }
    func testEnvironmentPrecedenceAndRootDoesNotRedirectSave() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        try h.write(" DM_SAVE_SYNC =0\r\nDM_SAVE_SYNC=/ignored\nDM_ROOT=/elsewhere\n", h.support.appendingPathComponent("env.txt"))
        try h.write("DM_SAVE_SYNC=/bundle\n", h.app.appendingPathComponent("Contents/Resources/dm/env.txt"))
        XCTAssertEqual(try h.location(gameCloud: "/own").root.path, h.support.path)
        XCTAssertThrowsError(try h.location(environment: ["DM_SAVE_SYNC": "/launch"]))
        XCTAssertThrowsError(try h.location(environment: ["DM_SAVE": "/elsewhere"]))
        XCTAssertThrowsError(try h.location(environment: ["DM_SAVE": ""]))
        XCTAssertNoThrow(try h.location(environment: ["DM_SAVE_SYNC": ""]))
        XCTAssertThrowsError(try h.location(environment: ["DM_SAVE_SYNC": " 0"]))
    }
    func testSymlinkedDestinationRefusedWithoutWriting() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let elsewhere = h.base.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: h.support, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: h.support.appendingPathComponent("save"), withDestinationURL: elsewhere)
        XCTAssertThrowsError(try h.location())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path), [])
    }
    func testSpecialConfigFileIsRefusedBeforeReading() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        try FileManager.default.createDirectory(at: h.support, withIntermediateDirectories: true)
        let pipe = h.support.appendingPathComponent("env.txt")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertThrowsError(try SaveFiles.safePath(pipe))
    }
    func testLibraryCloudAndUnreadableConfiguration() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        XCTAssertThrowsError(try h.location(libraryCloud: "/library"))
        try FileManager.default.createDirectory(at: h.support.appendingPathComponent("env.txt"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try h.location())
    }
}
