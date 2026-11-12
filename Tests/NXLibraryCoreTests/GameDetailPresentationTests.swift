import XCTest
@testable import NXLibraryCore

final class GameDetailPresentationTests: XCTestCase {
    func testKnownGenresTranslateInBothPresentationsWithoutChangingMetadata() {
        let old = L10n.context
        defer { L10n.setContext(old) }
        L10n.setContext(AppLocale(language: .italian, region: "IT"))
        let metadata = meta(genres: ["Adventure", "Action", "Role-Playing", "My custom genre"])
        let detail = GameDetailPresentation(game: game("Game"), metadata: metadata, totalPlaytime: 0, lastPlayed: nil)
        let library = LibraryPresentation(game: game("Game"), metadata: metadata, totalPlaytime: 0, lastPlayed: nil)
        XCTAssertEqual(detail.genres, ["Avventura", "Azione", "Giochi di ruolo", "My custom genre"])
        XCTAssertEqual(library.genres, ["Avventura", "Azione", "Giochi di ruolo"])
        XCTAssertEqual(metadata.genres.first, "Adventure")
        XCTAssertEqual(detail.descriptionLanguageNote, metadata.description.isEmpty ? nil : "Descrizione in inglese.")
    }

    func testRebuildIsUnavailableWhenRecordedSourceFilesAreMissing() {
        var missing = PortedGame(name: "Synthetic", url: URL(fileURLWithPath: "/Applications/Synthetic.app"),
                                 platform: .macApp, sizeBytes: 0, modificationDate: .distantPast)
        missing.status = .builtSourcesMissing
        missing.sources = [GameFileItem(url: URL(fileURLWithPath: "/missing-\(UUID())/base.nsp"), kind: .base, sizeBytes: 1)]
        let presentation = GameDetailPresentation(game: missing, metadata: nil, totalPlaytime: 0, lastPlayed: nil)
        XCTAssertTrue(presentation.canPlay)
        XCTAssertFalse(presentation.canRebuild)
    }

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

    func testAttachedSourcesAllowRebuild() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("base-\(UUID()).xci")
        try Data("synthetic".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        var game = PortedGame(name: "Game", url: URL(fileURLWithPath: "/tmp/Game.app"),
                              platform: .macApp, sizeBytes: 1,
                              modificationDate: Date(timeIntervalSince1970: 0),
                              titleId: "0100000000010000")
        game.status = .built
        game.sources = [GameFileItem(url: source,
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
        let it = GameDetailPresentation(game: g, metadata: m, totalPlaytime: 0, lastPlayed: nil,
                                        locale: Locale(identifier: "it_IT"))
        let gb = GameDetailPresentation(game: g, metadata: m, totalPlaytime: 0, lastPlayed: nil,
                                        locale: Locale(identifier: "en_GB"))
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

    func testSameNameEqualPlaytimeGetDistinctRanks() {
        let a = game("Twin"), b = game("Twin")
        let times: [UUID: TimeInterval] = [a.id: 60, b.id: 60]
        func rank(_ g: PortedGame) -> String? {
            GameDetailPresentation(game: g, metadata: nil, totalPlaytime: 60, lastPlayed: nil,
                                   libraryGames: [a, b], playtimeByGame: times).rank
        }
        XCTAssertEqual(Set([rank(a), rank(b)]), ["#1 of 2", "#2 of 2"])
    }

    func testThisWeekCountsOnlyMondayPartOfSpanningSession() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let monday = cal.date(from: DateComponents(year: 2026, month: 10, day: 26))!
        let now = monday.addingTimeInterval(3 * 3_600)
        let a = game("A")
        let s = PlaySession(gameID: a.id, titleID: "t", bundleID: nil,
                            startedAt: monday.addingTimeInterval(-3_600), endedAt: monday.addingTimeInterval(3_600),
                            lastHeartbeatAt: now)
        let p = GameDetailPresentation(game: a, metadata: nil, totalPlaytime: 7_200, lastPlayed: nil, now: now,
                                       sessions: [s], calendar: cal)
        XCTAssertEqual(p.thisWeek, "1h 0m")
    }
}
