import XCTest
@testable import NXLibraryCore

final class LibraryQueryTests: XCTestCase {
    private func game(_ name: String, status: GameStatus = .built,
                      modified: TimeInterval = 0,
                      sources: [GameFileItem] = [],
                      titleId: String? = nil,
                      bundleId: String? = nil) -> PortedGame {
        var g = PortedGame(
            name: name,
            url: URL(fileURLWithPath: "/tmp/\(name).app"),
            platform: .macApp,
            sizeBytes: 1,
            modificationDate: Date(timeIntervalSince1970: modified),
            bundleId: bundleId,
            titleId: titleId
        )
        g.status = status
        g.sources = sources
        return g
    }

    private func baseSource() -> GameFileItem {
        GameFileItem(url: URL(fileURLWithPath: "/tmp/base.xci"),
                     name: "base.xci", sizeBytes: 1, type: .base)
    }

    private struct StubHistory: PlayHistory {
        var dates: [UUID: Date] = [:]
        func lastPlayed(for gameID: UUID) -> Date? { dates[gameID] }
    }

    private func fixtures() -> (games: [PortedGame], history: StubHistory) {
        var zelda = game("Zelda")
        var mario = game("Mario")
        let animal = game("Animal")
        var hidden = game("Hidden", status: .appMissing)
        zelda.isFavorite = true
        hidden.isHidden = true
        hidden.isFavorite = true
        mario.status = .appMissing
        var h = StubHistory()
        h.dates[zelda.id] = Date(timeIntervalSince1970: 100)
        h.dates[mario.id] = Date(timeIntervalSince1970: 200)
        h.dates[hidden.id] = Date(timeIntervalSince1970: 300)
        return ([zelda, mario, animal, hidden], h)
    }

    func testAllSortsByLastPlayedThenName() {
        let (games, h) = fixtures()
        let extra = game("Banana")
        let result = LibraryQuery().apply(to: games + [extra], history: h)
        XCTAssertEqual(result.map(\.name), ["Mario", "Zelda", "Animal", "Banana"])
    }

    func testInstalledOnlyPlayable() {
        let (games, h) = fixtures()
        let result = LibraryQuery(filter: .installed).apply(to: games, history: h)
        XCTAssertEqual(result.map(\.name), ["Zelda", "Animal"])
    }

    func testRecentlyPlayedNewestFirstAndOnlyPlayed() {
        let (games, h) = fixtures()
        let result = LibraryQuery(filter: .recentlyPlayed).apply(to: games, history: h)
        XCTAssertEqual(result.map(\.name), ["Mario", "Zelda"])
    }

    func testFavoritesFilter() {
        let (games, h) = fixtures()
        let result = LibraryQuery(filter: .favorites).apply(to: games, history: h)
        XCTAssertEqual(result.map(\.name), ["Zelda"])
    }

    func testNotPlayedFilter() {
        let (games, h) = fixtures()
        let result = LibraryQuery(filter: .notPlayed).apply(to: games, history: h)
        XCTAssertEqual(result.map(\.name), ["Animal"])
    }

    func testHiddenExcludedEverywhere() {
        let (games, h) = fixtures()
        for filter in LibraryFilter.allCases {
            let result = LibraryQuery(filter: filter).apply(to: games, history: h)
            XCTAssertFalse(result.contains { $0.name == "Hidden" }, "\(filter)")
        }
        let searched = LibraryQuery(searchText: "Hidden").apply(to: games, history: h)
        XCTAssertTrue(searched.isEmpty)
    }

    func testSearchMatchesNameTitleAndBundleCaseInsensitively() {
        let games = [
            game("Super Mario Odyssey", titleId: "0100000000010000", bundleId: "org.nxnative.0100000000010000"),
            game("The Legend of Zelda", titleId: "01007EF00011E000")
        ]
        XCTAssertEqual(LibraryQuery(searchText: "mario").apply(to: games, history: NoPlayHistory()).map(\.name),
                       ["Super Mario Odyssey"])
        XCTAssertEqual(LibraryQuery(searchText: "01007ef").apply(to: games, history: NoPlayHistory()).map(\.name),
                       ["The Legend of Zelda"])
        XCTAssertEqual(LibraryQuery(searchText: "ORG.NXNATIVE").apply(to: games, history: NoPlayHistory()).map(\.name),
                       ["Super Mario Odyssey"])
    }

    func testSelectionPreservesGameAndFallsBackToFirst() {
        let games = [game("A"), game("B")]
        var state = LibrarySelectionState()
        state.selectedGameID = games[1].id
        XCTAssertEqual(state.reconcile(with: games, history: NoPlayHistory()).map(\.name), ["A", "B"])
        XCTAssertEqual(state.selectedGameID, games[1].id)

        state.query.searchText = "A"
        _ = state.reconcile(with: games, history: NoPlayHistory())
        XCTAssertEqual(state.selectedGameID, games[0].id)
    }

    func testSelectionMoveClamps() {
        let games = [game("A"), game("B"), game("C")]
        var state = LibrarySelectionState()
        state.selectedGameID = games[0].id
        XCTAssertEqual(state.move(by: 1, in: games, history: NoPlayHistory()), games[1].id)
        XCTAssertEqual(state.move(by: 10, in: games, history: NoPlayHistory()), games[2].id)
        XCTAssertEqual(state.move(by: -10, in: games, history: NoPlayHistory()), games[0].id)
    }

    func testSelectionJumpsToEnds() {
        let games = [game("A"), game("B"), game("C")]
        var state = LibrarySelectionState()
        state.selectedGameID = games[1].id
        XCTAssertEqual(state.jump(toEnd: true, in: games, history: NoPlayHistory()), games[2].id)
        XCTAssertEqual(state.jump(toEnd: false, in: games, history: NoPlayHistory()), games[0].id)
        var empty = LibrarySelectionState()
        XCTAssertNil(empty.jump(toEnd: true, in: [], history: NoPlayHistory()))
    }
}
