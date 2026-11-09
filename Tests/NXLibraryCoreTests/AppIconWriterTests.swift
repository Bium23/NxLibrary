import XCTest
import AppKit
@testable import NXLibraryCore

final class AppIconWriterTests: XCTestCase {
    private final class Runner: CommandRunning {
        var calls: [[String]] = []
        /// Exit status for each codesign call in turn; 0 once the list runs out.
        var codesignStatus: [Int32] = []
        var iconOutputs: [Data] = []

        func run(_ executable: URL, _ arguments: [String], environment: [String: String]?,
                 currentDirectory: URL?) throws -> CommandResult {
            calls.append([executable.lastPathComponent] + arguments)
            switch executable.lastPathComponent {
            case "iconutil":
                let output = iconOutputs.isEmpty ? Data("icns".utf8) : iconOutputs.removeFirst()
                try output.write(to: URL(fileURLWithPath: arguments[4]))
                return CommandResult(status: 0, stdout: "", stderr: "")
            case "codesign":
                let status = codesignStatus.isEmpty ? 0 : codesignStatus.removeFirst()
                return CommandResult(status: status, stdout: "", stderr: status == 0 ? "" : "boom: invalid\nmore")
            default:
                return CommandResult(status: 0, stdout: "", stderr: "")
            }
        }
    }

    private var root: URL!
    private var runner: Runner!
    private var writer: AppIconWriter!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AppIconWriterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        runner = Runner()
        writer = AppIconWriter(backups: root.appendingPathComponent("backups"), runner: runner)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeApp(icon: String? = nil) throws -> URL {
        let app = root.appendingPathComponent("Game.app")
        try? FileManager.default.removeItem(at: app)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("_CodeSignature"), withIntermediateDirectories: true)
        try Data("launcher".utf8).write(to: contents.appendingPathComponent("MacOS/nxnative"))
        try Data("seal".utf8).write(to: contents.appendingPathComponent("_CodeSignature/CodeResources"))
        var info: [String: Any] = ["CFBundleExecutable": "nxnative", "CFBundleIdentifier": "org.nxnative.test"]
        if let icon {
            info["CFBundleIconFile"] = "AppIcon"
            try Data(icon.utf8).write(to: contents.appendingPathComponent("Resources/AppIcon.icns"))
        }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    private func info(_ app: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private func icon(_ app: URL) -> String? {
        (try? Data(contentsOf: app.appendingPathComponent("Contents/Resources/AppIcon.icns")))
            .map { String(decoding: $0, as: UTF8.self) }
    }

    private var png: Data {
        let image = NSImage(size: NSSize(width: 40, height: 20))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 20).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testAppWithoutIconGetsOneAndRestoreRemovesIt() throws {
        let app = try makeApp()
        XCTAssertFalse(writer.hasOwnIcon(app))

        try writer.apply(image: png, to: app, key: "040074A01BF12000")
        XCTAssertEqual(icon(app), "icns")
        XCTAssertEqual(try info(app)["CFBundleIconFile"] as? String, "AppIcon")
        XCTAssertEqual(try info(app)[AppIconWriter.markKey] as? Bool, true)
        XCTAssertTrue(writer.showsWrittenIcon(app))
        XCTAssertFalse(writer.hasOwnIcon(app))
        let codesign = runner.calls.filter { $0[0] == "codesign" }
        XCTAssertEqual(codesign.first, ["codesign", "--force", "--sign", "-", app.path])
        XCTAssertEqual(codesign.last, ["codesign", "--verify", "--deep", "--strict", app.path])

        try writer.restore(app, key: "040074A01BF12000")
        XCTAssertNil(icon(app))
        XCTAssertNil(try info(app)["CFBundleIconFile"])
        XCTAssertNil(try info(app)[AppIconWriter.markKey])
        XCTAssertEqual(try info(app)["CFBundleIdentifier"] as? String, "org.nxnative.test")
    }

    func testMissingReplacementRemovesThePreviousPickAndKeepsAnIconlessAppUsable() throws {
        let app = try makeApp()
        try writer.apply(image: png, to: app, key: "game")
        XCTAssertTrue(writer.showsWrittenIcon(app))
        XCTAssertTrue(try writer.update(image: nil, app: app, key: "game"))
        XCTAssertNil(icon(app))
        XCTAssertNil(try info(app)["CFBundleIconFile"])
        XCTAssertFalse(writer.showsWrittenIcon(app))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/MacOS/nxnative").path))
        XCTAssertFalse(try writer.update(image: nil, app: app, key: "game"))
    }

    func testAutomaticReadsTheOriginalInsteadOfTheAppliedPick() throws {
        let app = try makeApp(icon: "original")
        let before = try XCTUnwrap(writer.originalIconURL(app, key: "game"))
        XCTAssertEqual(try Data(contentsOf: before), Data("original".utf8))
        try writer.apply(image: png, to: app, key: "game")
        let backedUp = try XCTUnwrap(writer.originalIconURL(app, key: "game"))
        XCTAssertEqual(try Data(contentsOf: backedUp), Data("original".utf8))
        XCTAssertNotEqual(backedUp, before)
        XCTAssertTrue(try writer.update(image: nil, app: app, key: "game"))
        XCTAssertEqual(icon(app), "original")
    }

    func testOwnIconIsKeptAndRestored() throws {
        let app = try makeApp(icon: "original")
        XCTAssertTrue(writer.hasOwnIcon(app))

        try writer.apply(image: png, to: app, key: "0100")
        // A second choice keeps the first backup: the game's own icon, not NX Library's.
        try writer.apply(image: png, to: app, key: "0100")
        XCTAssertEqual(icon(app), "icns")

        try writer.restore(app, key: "0100")
        XCTAssertEqual(icon(app), "original")
        XCTAssertEqual(try info(app)["CFBundleIconFile"] as? String, "AppIcon")
        XCTAssertTrue(writer.hasOwnIcon(app))
    }

    func testChangingFromAToBReplacesTheIconAndKeepsTheGamesOriginal() throws {
        let app = try makeApp(icon: "game original")
        runner.iconOutputs = [Data("icon A".utf8), Data("icon B".utf8)]
        try writer.apply(image: png, to: app, key: "0100")
        XCTAssertEqual(icon(app), "icon A")
        try writer.apply(image: png, to: app, key: "0100")
        XCTAssertEqual(icon(app), "icon B")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("backups/0100/original.icns")), "game original")
        try writer.restore(app, key: "0100")
        XCTAssertEqual(icon(app), "game original", "Automatic must not restore A instead of the game's original")
    }

    func testAutomaticThenAnotherPickStillRestoresAbsenceForAnIconlessGame() throws {
        let app = try makeApp()
        runner.iconOutputs = [Data("icon A".utf8), Data("icon B".utf8)]
        try writer.apply(image: png, to: app, key: "0400")
        XCTAssertEqual(icon(app), "icon A")
        try writer.restore(app, key: "0400")
        XCTAssertNil(icon(app))
        try writer.apply(image: png, to: app, key: "0400")
        XCTAssertEqual(icon(app), "icon B")
        try writer.restore(app, key: "0400")
        XCTAssertNil(icon(app))
        XCTAssertFalse(writer.showsWrittenIcon(app))
        XCTAssertFalse(writer.hasOriginalIcon(app, key: "0400"))
    }

    func testRebuiltAppReplacesTheKeptOriginal() throws {
        _ = try makeApp(icon: "old build")
        try writer.apply(image: png, to: root.appendingPathComponent("Game.app"), key: "0100")
        // A rebuild replaces the whole app: no mark, the new build's icon.
        let app = try makeApp(icon: "new build")
        try writer.apply(image: png, to: app, key: "0100")
        try writer.restore(app, key: "0100")
        XCTAssertEqual(icon(app), "new build")
    }

    func testFailedSigningLeavesTheAppAsItWas() throws {
        let app = try makeApp(icon: "original")
        let before = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        runner.codesignStatus = [0, 1]   // signs, then the verification fails

        XCTAssertThrowsError(try writer.apply(image: png, to: app, key: "0100")) { error in
            XCTAssertEqual(error as? AppIconWriter.Failure, .signingFailed("boom: invalid"))
        }
        XCTAssertEqual(icon(app), "original")
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), before)
        XCTAssertEqual(try String(contentsOf: app.appendingPathComponent("Contents/MacOS/nxnative")), "launcher")
    }

    func testOriginalIconIsRememberedIncludingItsAbsence() throws {
        let own = try makeApp(icon: "original")
        XCTAssertTrue(writer.hasOriginalIcon(own, key: "0100"))
        try writer.apply(image: png, to: own, key: "0100")
        XCTAssertTrue(writer.hasOriginalIcon(own, key: "0100"), "kept aside while the player's icon shows")

        let none = try makeApp()
        XCTAssertFalse(writer.hasOriginalIcon(none, key: "0400"))
        try writer.apply(image: png, to: none, key: "0400")
        XCTAssertFalse(writer.hasOriginalIcon(none, key: "0400"))
    }

    func testIconPickKeepsAppIconSize() throws {
        let picks = ArtworkPicks(directory: root.appendingPathComponent("picks"))
        let big = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2000, pixelsHigh: 2000, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let data = big.representation(using: .png, properties: [:])!
        let icon = try picks.save(data, titleID: "0400", slot: .icon)
        XCTAssertEqual(ArtworkCandidates.pixelSize(of: try Data(contentsOf: icon))?.width, 1024)
        let cover = try picks.save(data, titleID: "0400", slot: .background)
        XCTAssertEqual(ArtworkCandidates.pixelSize(of: try Data(contentsOf: cover))?.width, 2000)
    }

    /// Launcher art with a transparent margin and rounded corners becomes an opaque square filled to the edges, so
    /// macOS masks it like the engine's icons instead of shrinking it into a grey tile.
    func testIconArtIsTrimmedAndOpaque() throws {
        let size = 200
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(x: 20, y: 20, width: 160, height: 160), cornerWidth: 30, cornerHeight: 30, transform: nil))
        context.fillPath()
        let result = try AppIconWriter.fullBleed(context.makeImage()!)

        XCTAssertEqual(result.width, 200)
        XCTAssertEqual(result.height, 200)
        XCTAssertTrue([.none, .noneSkipLast, .noneSkipFirst].contains(result.alphaInfo))
        let read = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 800,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        read.draw(result, in: CGRect(x: 0, y: 0, width: 200, height: 200))
        let pixels = read.data!.bindMemory(to: UInt8.self, capacity: 200 * 200 * 4)
        for (x, y) in [(0, 0), (199, 0), (0, 199), (199, 199), (100, 100)] {
            let i = (y * 200 + x) * 4
            XCTAssertGreaterThan(pixels[i], 200, "red at \(x),\(y)")
            XCTAssertLessThan(pixels[i + 1], 40)
            XCTAssertEqual(pixels[i + 3], 255)
        }
    }

    func testRestoreWithoutWrittenIconDoesNothing() throws {
        let app = try makeApp(icon: "original")
        try writer.restore(app, key: "0100")
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertEqual(icon(app), "original")
    }

    func testNotAnImageAndNotAnApp() throws {
        let app = try makeApp()
        XCTAssertThrowsError(try writer.apply(image: Data("text".utf8), to: app, key: "k")) {
            XCTAssertEqual($0 as? AppIconWriter.Failure, .notAnImage)
        }
        XCTAssertNil(try info(app)[AppIconWriter.markKey])
        XCTAssertThrowsError(try writer.apply(image: png, to: root.appendingPathComponent("Missing.app"), key: "k")) {
            XCTAssertEqual($0 as? AppIconWriter.Failure, .notAnApp)
        }
    }
}
