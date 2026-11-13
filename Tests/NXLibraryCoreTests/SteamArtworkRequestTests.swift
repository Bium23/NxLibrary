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
}
