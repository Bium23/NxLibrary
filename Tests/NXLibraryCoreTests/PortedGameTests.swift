import XCTest
@testable import NXLibraryCore

final class PortedGameTests: XCTestCase {
    func testPlayableRequiresBuiltAppBundle() {
        var game = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/Game.app"),
                              platform: .macApp, sizeBytes: 1, modificationDate: Date())
        XCTAssertFalse(game.isPlayableLocally)

        game.status = .built
        XCTAssertTrue(game.isPlayableLocally)

        game.status = .builtSourcesMissing
        XCTAssertTrue(game.isPlayableLocally)

        game.status = .appMissing
        XCTAssertFalse(game.isPlayableLocally)

        game.status = .built
        game.url = URL(fileURLWithPath: "/tmp/workspace")
        XCTAssertFalse(game.isPlayableLocally)
    }

    func testDeleteSafetyForSourceFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXDelete-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Game.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        defer { try? FileManager.default.removeItem(at: root) }

        var game = PortedGame(name: "G", url: root.appendingPathComponent("workspace"),
                              platform: .macApp, sizeBytes: 1, modificationDate: Date())
        game.status = .notBuilt
        XCTAssertFalse(game.canDeleteAppBundle())

        game.status = .built
        game.url = app
        XCTAssertTrue(game.canDeleteAppBundle())

        game.workspacePath = app.path
        XCTAssertFalse(game.canDeleteAppBundle())

        game.workspacePath = nil
        game.sources = [GameFileItem(url: app.appendingPathComponent("source.nsp"),
                                     kind: .base, titleId: "0100000000010000", sizeBytes: 1)]
        XCTAssertFalse(game.canDeleteAppBundle())
    }
}
