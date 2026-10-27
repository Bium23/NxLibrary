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

    func testAllSortsByName() {
        let games = [game("Zelda"), game("Mario"), game("Animal")]
        let result = LibraryQuery().apply(to: games)
        XCTAssertEqual(result.map(\.name), ["Animal", "Mario", "Zelda"])
    }

    func testReadyOnlyIncludesPlayable() {
        let games = [
            game("Ready", status: .built),
            game("Missing", status: .appMissing),
            game("Not built", status: .notBuilt)
        ]
        let result = LibraryQuery(filter: .ready).apply(to: games)
        XCTAssertEqual(result.map(\.name), ["Ready"])
    }

    func testNeedsSourcesUsesBasePresence() {
        let games = [
            game("Detached"),
            game("Attached", sources: [baseSource()])
        ]
        let result = LibraryQuery(filter: .needsSources).apply(to: games)
        XCTAssertEqual(result.map(\.name), ["Detached"])
    }

    func testRecentlyAddedSortsNewestFirst() {
        let games = [game("Old", modified: 1), game("New", modified: 3), game("Mid", modified: 2)]
        let result = LibraryQuery(filter: .recentlyAdded).apply(to: games)
        XCTAssertEqual(result.map(\.name), ["New", "Mid", "Old"])
    }

    func testSearchMatchesNameTitleAndBundleCaseInsensitively() {
        let games = [
            game("Super Mario Odyssey", titleId: "0100000000010000", bundleId: "org.nxnative.0100000000010000"),
            game("The Legend of Zelda", titleId: "01007EF00011E000")
        ]
        XCTAssertEqual(LibraryQuery(searchText: "mario").apply(to: games).map(\.name),
                       ["Super Mario Odyssey"])
        XCTAssertEqual(LibraryQuery(searchText: "01007ef").apply(to: games).map(\.name),
                       ["The Legend of Zelda"])
        XCTAssertEqual(LibraryQuery(searchText: "ORG.NXNATIVE").apply(to: games).map(\.name),
                       ["Super Mario Odyssey"])
    }

    func testSelectionPreservesGameAndFallsBackToFirst() {
        let games = [game("A"), game("B")]
        var state = LibrarySelectionState()
        state.selectedGameID = games[1].id
        XCTAssertEqual(state.reconcile(with: games).map(\.name), ["A", "B"])
        XCTAssertEqual(state.selectedGameID, games[1].id)

        state.query.searchText = "A"
        _ = state.reconcile(with: games)
        XCTAssertEqual(state.selectedGameID, games[0].id)
    }

    func testSelectionMoveClamps() {
        let games = [game("A"), game("B"), game("C")]
        var state = LibrarySelectionState()
        state.selectedGameID = games[0].id
        XCTAssertEqual(state.move(by: 1, in: games), games[1].id)
        XCTAssertEqual(state.move(by: 10, in: games), games[2].id)
        XCTAssertEqual(state.move(by: -10, in: games), games[0].id)
    }
}
