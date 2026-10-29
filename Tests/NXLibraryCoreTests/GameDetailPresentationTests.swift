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

    // MARK: Selene details data

    private func game(_ name: String, hidden: Bool = false) -> PortedGame {
        var g = PortedGame(name: name, url: URL(fileURLWithPath: "/tmp/\(name).app"),
                           platform: .macApp, sizeBytes: 1,
                           modificationDate: Date(timeIntervalSince1970: 0))
        g.isHidden = hidden
        return g
    }

    private func meta(developers: [String] = [], publishers: [String] = [],
                      genres: [String] = [], releaseDate: String? = nil) -> NintendoStoreMetadata {
        NintendoStoreMetadata(titleId: "0100", name: "X", description: "", developers: developers,
                              publishers: publishers, genres: genres, releaseDate: releaseDate,
                              storeURL: URL(string: "https://example.com")!, imageURL: nil,
                              headerImageURL: nil, nsuid: nil, fetchedAt: Date(timeIntervalSince1970: 0))
    }

    func testReleasedFormatsStoreDate() {
        let g = game("A")
        let m = meta(releaseDate: "2017-03-03")
        let utc = TimeZone(identifier: "UTC")!
        let it = GameDetailPresentation(game: g, metadata: m, totalPlaytime: 0, lastPlayed: nil,
                                        locale: Locale(identifier: "it_IT"), timeZone: utc)
        let gb = GameDetailPresentation(game: g, metadata: m, totalPlaytime: 0, lastPlayed: nil,
                                        locale: Locale(identifier: "en_GB"), timeZone: utc)
        XCTAssertEqual(it.released, "03/03/17")
        XCTAssertEqual(gb.released, "03/03/2017")
        let bad = GameDetailPresentation(game: g, metadata: meta(releaseDate: "soon"),
                                         totalPlaytime: 0, lastPlayed: nil)
        XCTAssertNil(bad.released)
        XCTAssertNil(GameDetailPresentation(game: g, metadata: nil, totalPlaytime: 0, lastPlayed: nil).released)
    }

    func testDeveloperFallsBackToPublisher() {
        let g = game("A")
        func line(_ m: NintendoStoreMetadata?) -> String? {
            GameDetailPresentation(game: g, metadata: m, totalPlaytime: 0, lastPlayed: nil).developerLine
        }
        XCTAssertEqual(line(meta(developers: ["Nintendo", " "], publishers: ["P"])), "Nintendo")
        XCTAssertEqual(line(meta(developers: ["A", "B"])), "A, B")
        XCTAssertEqual(line(meta(developers: [" "], publishers: ["P1", "P2"])), "P1, P2")
        XCTAssertNil(line(meta()))
        XCTAssertNil(line(nil))
        let p = GameDetailPresentation(game: g, metadata: meta(genres: ["Action", "Other", "RPG", "Action"]),
                                       totalPlaytime: 0, lastPlayed: nil)
        XCTAssertEqual(p.genres, ["Action", "RPG"])
    }

    func testRankAmongPlayedGames() {
        let a = game("A"), b = game("B"), c = game("C"), d = game("D"), hidden = game("H", hidden: true)
        let times: [UUID: TimeInterval] = [a.id: 100, b.id: 300, c.id: 100, d.id: 0, hidden.id: 9_999]
        func rank(_ g: PortedGame) -> String? {
            GameDetailPresentation(game: g, metadata: nil, totalPlaytime: times[g.id] ?? 0, lastPlayed: nil,
                                   libraryGames: [a, b, c, d, hidden], playtimeByGame: times).rank
        }
        XCTAssertEqual(rank(b), "#1 of 3")
        XCTAssertEqual(rank(a), "#2 of 3")
        XCTAssertEqual(rank(c), "#3 of 3")
    }

    func testUnplayedHasNoRank() {
        let a = game("A"), b = game("B")
        let p = GameDetailPresentation(game: a, metadata: nil, totalPlaytime: 0, lastPlayed: nil,
                                       libraryGames: [a, b], playtimeByGame: [b.id: 60])
        XCTAssertNil(p.rank)
    }

    func testThisWeekUsesMondayFirstWeek() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // Wednesday 2026-10-28 12:00 UTC; week starts Monday 2026-10-26.
        let now = Date(timeIntervalSince1970: 1_793_188_800)
        let a = game("A")
        let s1 = PlaySession(gameID: a.id, titleID: "t", bundleID: nil,
                             startedAt: now.addingTimeInterval(-3_600), endedAt: now.addingTimeInterval(-1_800),
                             lastHeartbeatAt: now)
        let old = PlaySession(gameID: a.id, titleID: "t", bundleID: nil,
                              startedAt: now.addingTimeInterval(-86_400 * 10),
                              endedAt: now.addingTimeInterval(-86_400 * 10 + 7_200), lastHeartbeatAt: now)
        let other = PlaySession(gameID: UUID(), titleID: "t", bundleID: nil,
                                startedAt: now.addingTimeInterval(-3_600), endedAt: now, lastHeartbeatAt: now)
        let p = GameDetailPresentation(game: a, metadata: nil, totalPlaytime: 9_000, lastPlayed: nil, now: now,
                                       sessions: [s1, old, other], calendar: cal)
        XCTAssertEqual(p.thisWeek, "30m")
        let none = GameDetailPresentation(game: a, metadata: nil, totalPlaytime: 0, lastPlayed: nil, now: now,
                                          sessions: [], calendar: cal)
        XCTAssertEqual(none.thisWeek, "—")
    }
}
