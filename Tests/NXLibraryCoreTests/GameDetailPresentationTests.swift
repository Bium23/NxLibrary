import XCTest
@testable import NXLibraryCore

final class GameDetailPresentationTests: XCTestCase {
    func testBuildAndSourceState() {
        var game = PortedGame(name: "Game", url: URL(fileURLWithPath: "/tmp/Game.app"),
                              platform: .macApp, sizeBytes: 18_000_000_000,
                              modificationDate: Date(timeIntervalSince1970: 0),
                              titleId: "0100000000010000")
        game.status = .builtSourcesMissing
        game.versionString = "1.9.0"
        game.toolchain = ToolchainInfo(engineCommit: "1963fab", metalVersion: "32023.921",
                                       xcodeVersion: "27.1", verified: true,
                                       note: "Certified toolchain")
        let p = GameDetailPresentation(game: game, metadata: nil,
                                       totalPlaytime: 3_600,
                                       lastPlayed: Date(timeIntervalSince1970: 0),
                                       now: Date(timeIntervalSince1970: 7_200))
        XCTAssertTrue(p.canPlay)
        XCTAssertFalse(p.canRebuild)
        XCTAssertTrue(p.sourcesDetached)
        XCTAssertEqual(p.engineCommitShort, "1963fab")
        XCTAssertEqual(p.version, "1.9.0")
        XCTAssertEqual(p.playtime, "1h 0m")
        XCTAssertTrue(p.size.contains("18"))
    }

    func testAttachedSourcesAllowRebuild() {
        var game = PortedGame(name: "Game", url: URL(fileURLWithPath: "/tmp/Game.app"),
                              platform: .macApp, sizeBytes: 1,
                              modificationDate: Date(timeIntervalSince1970: 0),
                              titleId: "0100000000010000")
        game.status = .built
        game.sources = [GameFileItem(url: URL(fileURLWithPath: "/tmp/base.xci"),
                                     name: "base.xci", sizeBytes: 1, type: .base)]
        let p = GameDetailPresentation(game: game, metadata: nil,
                                       totalPlaytime: 0, lastPlayed: nil)
        XCTAssertTrue(p.canRebuild)
        XCTAssertFalse(p.sourcesDetached)
    }
}
