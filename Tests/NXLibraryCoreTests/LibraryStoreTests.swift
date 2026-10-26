import XCTest
@testable import NXLibraryCore

final class LibraryStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXLibraryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testSaveLoadAndMergePreservesSettings() throws {
        let store = LibraryStore(directory: dir)
        var game = PortedGame(
            name: "The Legend of Zelda: Breath of the Wild",
            url: URL(fileURLWithPath: "/tmp/game.app"),
            platform: .macApp,
            sizeBytes: 17,
            modificationDate: Date(timeIntervalSince1970: 1),
            bundleId: "org.nxnative.01007ef00011e000",
            titleId: "01007EF00011E000",
            versionString: "1.9.0"
        )
        game.status = .builtSourcesMissing
        game.settings.metalHUD = true
        try store.save(LibraryFile(schemaVersion: 1, games: [game]))
        let loaded = try store.load()
        XCTAssertEqual(loaded.games.first?.status, .builtSourcesMissing)
        XCTAssertEqual(loaded.games.first?.settings.metalHUD, true)

        var scanned = game
        scanned.status = .built
        scanned.settings = GameRuntimeConfig()
        let merged = try store.merge(scanned: [scanned])
        XCTAssertEqual(merged.games.first?.status, .built)
        XCTAssertEqual(merged.games.first?.settings.metalHUD, true)
        XCTAssertEqual(merged.games.count, 1)
    }

    func testCorruptFileRestoresBackup() throws {
        let store = LibraryStore(directory: dir)
        var game = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/g.app"),
                              platform: .macApp, sizeBytes: 1, modificationDate: Date())
        game.titleId = "0100000000010000"
        try store.save(LibraryFile(schemaVersion: 1, games: [game]))
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(try store.load().games.count, 1)
    }
}
