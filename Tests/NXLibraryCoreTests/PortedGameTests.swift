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
}
