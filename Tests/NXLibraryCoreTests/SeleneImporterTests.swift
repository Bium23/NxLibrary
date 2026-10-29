import XCTest
@testable import NXLibraryCore

final class SeleneImporterTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("SeleneImporter-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func write(_ path: String, _ text: String = "x") throws {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func makeSelene(sounds: [String] = SeleneImporter.soundFiles) throws -> URL {
        try write("selene/theme/theme.yaml")
        for name in sounds { try write("selene/theme/Audio/\(name).wav", name) }
        try write("selene/theme/Wallpapers/nord/1-aurora.jpg")
        try write("selene/theme/Wallpapers/gruvbox/2-flower.png")
        return root.appendingPathComponent("selene")
    }

    private var destination: URL { root.appendingPathComponent("imports") }

    func testRejectsNonSeleneFolder() throws {
        try write("other/readme.txt")
        let importer = SeleneImporter(destination: destination)
        XCTAssertThrowsError(try importer.importFrom(seleneRoot: root.appendingPathComponent("other"))) {
            XCTAssertEqual($0 as? SeleneImportError, .notASeleneFolder)
        }
        XCTAssertFalse(fm.fileExists(atPath: destination.path))
    }

    func testCopiesSoundsAndWallpapers() throws {
        let selene = try makeSelene()
        let report = try SeleneImporter(destination: destination).importFrom(seleneRoot: selene)
        XCTAssertEqual(report.missing, [])
        XCTAssertEqual(Set(report.copied), Set(SeleneImporter.soundFiles.map { "Sounds/\($0).wav" }
            + ["Wallpapers/nord/1-aurora.jpg", "Wallpapers/gruvbox/2-flower.png"]))
        XCTAssertTrue(fm.fileExists(atPath: destination.appendingPathComponent("Sounds/GameReady.wav").path))
        XCTAssertTrue(fm.fileExists(atPath: destination.appendingPathComponent("Wallpapers/nord/1-aurora.jpg").path))
    }

    func testPartialFolderReportsMissing() throws {
        let selene = try makeSelene(sounds: ["OpenPanel", "Alert"])
        let report = try SeleneImporter(destination: destination).importFrom(seleneRoot: selene)
        XCTAssertTrue(report.copied.contains("Sounds/OpenPanel.wav"))
        XCTAssertEqual(Set(report.missing),
                       Set(SeleneImporter.soundFiles.filter { $0 != "OpenPanel" && $0 != "Alert" }
                            .map { "Sounds/\($0).wav" }))
    }

    func testReimportOverwritesAndKeepsOthers() throws {
        let selene = try makeSelene()
        let importer = SeleneImporter(destination: destination)
        _ = try importer.importFrom(seleneRoot: selene)
        let keep = destination.appendingPathComponent("Sounds/Mine.wav")
        try Data("mine".utf8).write(to: keep)
        try write("selene/theme/Audio/Alert.wav", "new")
        _ = try importer.importFrom(seleneRoot: selene)
        let alert = try String(contentsOf: destination.appendingPathComponent("Sounds/Alert.wav"))
        XCTAssertEqual(alert, "new")
        XCTAssertTrue(fm.fileExists(atPath: keep.path))
    }

    func testCueResolutionPrefersImportThenBundleThenFallback() throws {
        let imports = root.appendingPathComponent("imports/Sounds")
        let bundled = root.appendingPathComponent("bundle/Sounds")
        try write("imports/Sounds/OpenPanel.wav")
        try write("bundle/Sounds/Success.wav")
        try write("bundle/Sounds/Key.wav")
        try write("bundle/Sounds/navigation.wav")
        let resolver = SoundCueResolver(importedSounds: imports, bundledSounds: bundled)
        XCTAssertEqual(resolver.url(for: .openPanel)?.lastPathComponent, "OpenPanel.wav")
        XCTAssertEqual(resolver.url(for: .openPanel)?.deletingLastPathComponent().path, imports.path)
        XCTAssertEqual(resolver.url(for: .move)?.lastPathComponent, "navigation.wav")
        XCTAssertEqual(resolver.url(for: .gameReady)?.lastPathComponent, "Success.wav")
        XCTAssertEqual(resolver.url(for: .back)?.lastPathComponent, "Key.wav")
        XCTAssertNil(resolver.url(for: .boot))
    }
}
