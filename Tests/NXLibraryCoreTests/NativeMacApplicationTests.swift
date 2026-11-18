import XCTest
import Darwin
@testable import NXLibraryCore

final class NativeMacApplicationTests: XCTestCase {
    func testIdentifiesArm64GameAndPreservesItsBundleIdentity() throws {
        let fixture = try SteamTestFixture.temporary(in: self)
        let app = try fixture.app()
        let result = try NativeMacApplication.inspect(at: app, within: fixture.root)
        XCTAssertEqual(result.url.path, app.path)
        XCTAssertEqual(result.bundleIdentifier, "test.game")
        XCTAssertEqual(result.name, "Fixture game")
        XCTAssertEqual(result.architectures, [.arm64])
        XCTAssertTrue(result.isDeclaredGame)
    }

    func testRecognizesIntelAndUniversalExecutables() throws {
        let fixture = try SteamTestFixture.temporary(in: self)
        let intel = try fixture.app(at: "Intel.app", cpuTypes: [0x01000007])
        let universal = try fixture.app(at: "Universal.app", cpuTypes: [0x01000007, 0x0100000c])
        XCTAssertEqual(try NativeMacApplication.inspect(at: intel, within: fixture.root).architectures, [.x86_64])
        XCTAssertEqual(try NativeMacApplication.inspect(at: universal, within: fixture.root).architectures, [.x86_64, .arm64])
    }

    func testDoesNotClassifyToolsOrUnclassifiedAppsAsGames() throws {
        let fixture = try SteamTestFixture.temporary(in: self)
        for (i, category) in ["public.app-category.developer-tools", nil, "public.app-category.not-games"].enumerated() {
            let app = try fixture.app(at: "Tool\(i).app", category: category)
            XCTAssertFalse(try NativeMacApplication.inspect(at: app, within: fixture.root).isDeclaredGame)
        }
        let action = try fixture.app(at: "Action.app", category: "public.app-category.action-games")
        XCTAssertTrue(try NativeMacApplication.inspect(at: action, within: fixture.root).isDeclaredGame)
    }

    func testRejectsNonAppsAndIosOnlyBundles() throws {
        let fixture = try SteamTestFixture.temporary(in: self)
        let invalid: [[String: Any]] = [["CFBundlePackageType": "BNDL"], ["LSRequiresIPhoneOS": true],
                                      ["CFBundleSupportedPlatforms": ["iPhoneOS"]]]
        for (i, metadata) in invalid.enumerated() {
            let app = try fixture.app(at: "Invalid\(i).app", metadata: metadata)
            XCTAssertThrowsError(try NativeMacApplication.inspect(at: app, within: fixture.root))
        }
    }

    func testRejectsMissingNonExecutableAndUnsupportedCpuFiles() throws {
        let fixture = try SteamTestFixture.temporary(in: self)
        let missing = try fixture.app(at: "Missing.app")
        try FileManager.default.removeItem(at: missing.appendingPathComponent("Contents/MacOS/fixture"))
        XCTAssertThrowsError(try NativeMacApplication.inspect(at: missing, within: fixture.root))
        let wrong = try fixture.app(at: "Wrong.app")
        try Data("not Mach-O".utf8).write(to: wrong.appendingPathComponent("Contents/MacOS/fixture"))
        XCTAssertThrowsError(try NativeMacApplication.inspect(at: wrong, within: fixture.root))
        let unsupported = try fixture.app(at: "Unsupported.app", cpuTypes: [12])
        XCTAssertThrowsError(try NativeMacApplication.inspect(at: unsupported, within: fixture.root))
        let library = try fixture.app(at: "Library.app")
        try SteamTestFixture.machHeader(cpu: 0x0100000c, fileType: 6)
            .write(to: library.appendingPathComponent("Contents/MacOS/fixture"))
        XCTAssertThrowsError(try NativeMacApplication.inspect(at: library, within: fixture.root))
    }

    func testRejectsExecutableTraversalAndSymlinkEscape() throws {
        let fixture = try SteamTestFixture.temporary(in: self)
        let app = try fixture.app(metadata: ["CFBundleExecutable": "../fixture"])
        XCTAssertThrowsError(try NativeMacApplication.inspect(at: app, within: fixture.root))
        let valid = try fixture.app(at: "Valid.app")
        let narrowRoot = fixture.root.appendingPathComponent("narrow")
        try FileManager.default.createDirectory(at: narrowRoot, withIntermediateDirectories: true)
        let link = narrowRoot.appendingPathComponent("Escaping.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: valid)
        XCTAssertThrowsError(try NativeMacApplication.inspect(at: link, within: narrowRoot))
    }

    func testRejectsOversizedMetadataAndTruncatedFatSlices() throws {
        let fixture = try SteamTestFixture.temporary(in: self)
        let app = try fixture.app()
        try Data(repeating: 65, count: 1024 * 1024 + 1).write(to: app.appendingPathComponent("Contents/Info.plist"))
        XCTAssertThrowsError(try NativeMacApplication.inspect(at: app, within: fixture.root))
        let fat = try fixture.app(at: "Truncated.app", cpuTypes: [0x01000007, 0x0100000c])
        let bytes = SteamTestFixture.fatHeader(cpus: [0x01000007, 0x0100000c]).dropLast(20)
        try Data(bytes).write(to: fat.appendingPathComponent("Contents/MacOS/fixture"))
        XCTAssertThrowsError(try NativeMacApplication.inspect(at: fat, within: fixture.root))
    }

    func testNonRegularMetadataDoesNotBlockWaitingForAWriter() throws {
        let fixture = try SteamTestFixture.temporary(in: self)
        let app = try fixture.app()
        let plist = app.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.removeItem(at: plist)
        XCTAssertEqual(mkfifo(plist.path, 0o600), 0)
        let finished = expectation(description: "Inspection rejects a FIFO without blocking")
        DispatchQueue.global().async {
            do {
                _ = try NativeMacApplication.inspect(at: app, within: fixture.root)
                XCTFail("A FIFO is not app metadata")
            } catch {}
            finished.fulfill()
        }
        let result = XCTWaiter.wait(for: [finished], timeout: 1)
        // Release an old blocking implementation so a failed test leaves no blocked worker behind.
        if result != .completed {
            let writer = Darwin.open(plist.path, O_WRONLY | O_NONBLOCK)
            if writer >= 0 { Darwin.close(writer) }
        }
        XCTAssertEqual(result, .completed)
    }
}
