import XCTest
import AppKit
@testable import NXLibraryCore

final class SteamArtworkRequestTests: XCTestCase {
    func testSquareUsesOriginalBundleAssetButPortraitNeverUsesIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Fixture.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIconFile":"Original"], format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let icon = resources.appendingPathComponent("Original.icns")
        try Data("fixture".utf8).write(to: icon)
        let observed = NativeMacApplication(url: app, executableURL: app.appendingPathComponent("Contents/MacOS/main"), bundleIdentifier: "fixture", name: "Fixture", architectures: [.arm64], isDeclaredGame: true, fileObservations: [])
        let native = CatalogNativeApplication(observed)
        let install = SteamCatalogInstallation(libraryURL: root, contentURL: root, applications: [native], availability: .available)
        var steam = SteamCatalogGame(appID: 10, name: "Fixture"); steam.installations = [install]; steam.hasBeenRecognized = true
        let game = CatalogGame(steam: steam), picks = SteamPersonalizationStore(directory: root.appendingPathComponent("picks"))
        XCTAssertEqual(SteamArtworkRequest(game: game, role: .square).localURL(picks: picks), icon)
        XCTAssertNil(SteamArtworkRequest(game: game, role: .cover).localURL(picks: picks))
        XCTAssertNotEqual(SteamArtworkRequest(game: game, role: .square).key, SteamArtworkRequest(game: game, role: .cover).key)
        // A malicious icon path is not a request to read outside the bundle.
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIconFile":"../../outside"], format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        XCTAssertNil(SteamArtworkRequest(game: game, role: .square).localURL(picks: picks))
    }

    func testPersonalPickComesBeforeTheAppIcon() throws {
        let (root, game, icon) = try fixture(iconName: "Original")
        defer { try? FileManager.default.removeItem(at: root) }
        let picks = SteamPersonalizationStore(directory: root.appendingPathComponent("picks"))
        XCTAssertEqual(SteamArtworkRequest(game: game, role: .square).localURL(picks: picks), icon)
        let png = try XCTUnwrap(Self.png())
        try picks.save(fields: [:], images: [.icon: png, .cover: png], automatic: [], titleID: game.personalizationReference.key)
        let square = try XCTUnwrap(SteamArtworkRequest(game: game, role: .square).localURL(picks: picks))
        XCTAssertNotEqual(square, icon)
        XCTAssertTrue(square.path.hasPrefix(root.appendingPathComponent("picks").path))
        XCTAssertNotNil(SteamArtworkRequest(game: game, role: .cover).localURL(picks: picks))
        XCTAssertNil(SteamArtworkRequest(game: game, role: .hero).localURL(picks: picks))
    }

    func testIconLinkLeavingTheBundleIsNotFollowed() throws {
        let (root, game, icon) = try fixture(iconName: "Original.icns")
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside.icns")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.removeItem(at: icon)
        try FileManager.default.createSymbolicLink(at: icon, withDestinationURL: outside)
        let picks = SteamPersonalizationStore(directory: root.appendingPathComponent("picks"))
        XCTAssertNil(SteamArtworkRequest(game: game, role: .square).localURL(picks: picks))
    }

    private func fixture(iconName: String) throws -> (URL, CatalogGame, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Fixture.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIconFile": iconName], format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let icon = resources.appendingPathComponent("Original.icns")
        try Data("fixture".utf8).write(to: icon)
        let observed = NativeMacApplication(url: app, executableURL: app.appendingPathComponent("Contents/MacOS/main"), bundleIdentifier: "fixture", name: "Fixture", architectures: [.arm64], isDeclaredGame: true, fileObservations: [])
        let install = SteamCatalogInstallation(libraryURL: root, contentURL: root, applications: [CatalogNativeApplication(observed)], availability: .available)
        var steam = SteamCatalogGame(appID: 10, name: "Fixture"); steam.installations = [install]; steam.hasBeenRecognized = true
        return (root, CatalogGame(steam: steam), icon)
    }

    private static func png() -> Data? {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 8, height: 8).fill(); image.unlockFocus()
        return image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
    }
}
