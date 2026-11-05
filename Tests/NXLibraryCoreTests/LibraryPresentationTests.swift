import XCTest
@testable import NXLibraryCore

final class LibraryPresentationTests: XCTestCase {
    private func game() -> PortedGame {
        var g = PortedGame(name: "The Legend of Zelda: Breath of the Wild",
                           url: URL(fileURLWithPath: "/tmp/BotW.app"),
                           platform: .macApp, sizeBytes: 1,
                           modificationDate: Date(timeIntervalSince1970: 0),
                           titleId: "01007EF00011E000")
        g.status = .builtSourcesMissing
        return g
    }

    private func metadata() -> NintendoStoreMetadata {
        NintendoStoreMetadata(
            titleId: "01007EF00011E000",
            name: "The Legend of Zelda: Breath of the Wild",
            description: "A world of discovery.",
            developers: ["Nintendo"],
            publishers: ["Nintendo"],
            genres: ["Adventure", "Action", "Role-Playing", "Other"],
            releaseDate: "2017-03-03T08:00:00.000Z",
            storeURL: URL(string: "https://www.nintendo.com/games/detail/botw/")!,
            imageURL: URL(string: "https://example.com/box.jpg"),
            headerImageURL: URL(string: "https://example.com/hero.jpg"),
            nsuid: "70010000000025",
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testPresentationFormatsRealMetadataAndPlayStats() {
        let now = Date(timeIntervalSince1970: 4_000)
        let presentation = LibraryPresentation(
            game: game(),
            metadata: metadata(),
            totalPlaytime: 8_400,
            lastPlayed: now.addingTimeInterval(-3_600),
            now: now
        )
        XCTAssertEqual(presentation.title, "The Legend of Zelda: Breath of the Wild")
        XCTAssertEqual(presentation.eyebrow, "The Legend of Zelda")
        XCTAssertEqual(presentation.genres.prefix(3).map { $0 }, ["Adventure", "Action", "Role-Playing"])
        XCTAssertEqual(presentation.publisher, "Nintendo")
        XCTAssertEqual(presentation.releaseYear, "2017")
        XCTAssertEqual(presentation.playtime, "2h 20m")
        XCTAssertEqual(presentation.lastPlayed, "1h ago")
        XCTAssertTrue(presentation.sourcesDetached)
        XCTAssertEqual(presentation.platform, "nxnative")
        XCTAssertEqual(presentation.console, "Nintendo Switch")
        XCTAssertEqual(presentation.summary, "A world of discovery.")
    }

    func testPresentationWithoutMetadataOrHistory() {
        let presentation = LibraryPresentation(
            game: game(), metadata: nil, totalPlaytime: 0,
            lastPlayed: nil, now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(presentation.eyebrow, "")
        XCTAssertTrue(presentation.genres.isEmpty)
        XCTAssertNil(presentation.publisher)
        XCTAssertNil(presentation.releaseYear)
        XCTAssertEqual(presentation.playtime, "—")
        XCTAssertEqual(presentation.lastPlayed, "Never")
        XCTAssertTrue(presentation.summary.isEmpty)
    }
}
