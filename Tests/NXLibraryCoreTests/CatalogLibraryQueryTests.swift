import XCTest
@testable import NXLibraryCore

final class CatalogLibraryQueryTests: XCTestCase {
    private func games() -> [CatalogGame] {
        var nx = CatalogTestSupport.completeLegacyGame(); nx.isHidden = false; nx.isFavorite = false
        var steam = SteamCatalogGame(appID: 10, name: "Árena"); steam.hasBeenRecognized = true; steam.isFavorite = true
        return [.init(nxnative: nx), .init(steam: steam)]
    }
    func testMixedProjectionRespectsEnabledHiddenAndRecognizedStates() throws {
        var records = games()
        let enabled: [CatalogSourceConfiguration] = [.init(integration: .nxnative, isEnabled: true), .init(integration: .steam, isEnabled: true, rootURL: URL(fileURLWithPath: "/tmp/Steam"))]
        XCTAssertEqual(CatalogLibraryProjection.visible(games: records, sources: enabled).count, 2)
        XCTAssertEqual(CatalogLibraryProjection.visible(games: records, sources: [.init(integration: .nxnative, isEnabled: true)]).count, 1)
        records[1].setHidden(true)
        XCTAssertEqual(CatalogLibraryProjection.visible(games: records, sources: enabled).count, 1)
        records.append(.init(steam: SteamCatalogGame(appID: 20, name: "Unclassified")))
        XCTAssertEqual(CatalogLibraryProjection.visible(games: records, sources: enabled).count, 1)
    }
    func testSearchAndFavoriteFilterUseSharedCatalogSemantics() {
        let records = games()
        XCTAssertEqual(LibraryQuery(searchText: "arena").applyCatalog(to: records, history: NoPlayHistory()).map(\.integration), [.steam])
        XCTAssertEqual(LibraryQuery(filter: .favorites).applyCatalog(to: records, history: NoPlayHistory()).map(\.integration), [.steam])
        XCTAssertEqual(LibraryQuery(searchText: "10").applyCatalog(to: records, history: NoPlayHistory()).map(\.integration), [.steam, .nxnative]) // both external IDs contain 10
    }
    func testCatalogSelectionAndSpotlightOrderKeepSteamIdentity() {
        let records = games()
        var selection = LibrarySelectionState(selectedGameID: records[1].id)
        _ = selection.reconcileCatalog(with: records, history: NoPlayHistory())
        XCTAssertEqual(selection.selectedGameID, records[1].id)
        let row = SpotlightRow.build(gameIDs: records.map(\.id), enabledCards: [], order: [SpotlightItem.game(records[1].id).key])
        XCTAssertEqual(Set(row), Set(records.map { SpotlightItem.game($0.id) }))
        _ = selection.reconcileCatalog(with: [records[0]], history: NoPlayHistory())
        XCTAssertEqual(selection.selectedGameID, records[0].id)
    }
    func testInstalledAndHistoryFiltersDoNotInferSteamPlayFromDiscovery() {
        let records = games()
        struct History: PlayHistory {
            let played: UUID
            func lastPlayed(for id: UUID) -> Date? { id == played ? Date(timeIntervalSince1970: 100) : nil }
        }
        let history = History(played: records[1].id)
        XCTAssertEqual(LibraryQuery(filter: .installed).applyCatalog(to: records, history: history).map(\.integration), [.nxnative])
        XCTAssertEqual(LibraryQuery(filter: .recentlyPlayed).applyCatalog(to: records, history: history).map(\.integration), [.steam])
        XCTAssertEqual(LibraryQuery(filter: .notPlayed).applyCatalog(to: records, history: history).map(\.integration), [.nxnative])
        XCTAssertTrue(LibraryQuery(filter: .recentlyPlayed).applyCatalog(to: records, history: NoPlayHistory()).isEmpty)
    }

}
