import XCTest
@testable import NXLibraryCore

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private struct FakeHistory: PlayHistory {
    var played: [UUID: Date] = [:]
    func lastPlayed(for gameID: UUID) -> Date? { played[gameID] }
}

final class SpotlightRowTests: XCTestCase {
    private func game(_ name: String, playable: Bool = true, hidden: Bool = false) -> PortedGame {
        var g = PortedGame(name: name,
                           url: URL(fileURLWithPath: "/tmp/\(name).app"),
                           platform: .macApp, sizeBytes: 1,
                           modificationDate: Date(timeIntervalSince1970: 1),
                           bundleId: nil, titleId: nil, versionString: nil)
        g.status = playable ? .builtSourcesMissing : .notBuilt
        g.isHidden = hidden
        return g
    }

    func testCardsThenGames() {
        let a = game("a"), b = game("b")
        let row = SpotlightRow.build(games: [a, b],
                                     enabledCards: [.surprise, .activity, .addGame],
                                     order: [])
        XCTAssertEqual(row, [.card(.surprise), .card(.activity), .card(.addGame), .game(a.id), .game(b.id)])
    }

    func testDisabledCardsDropped() {
        let a = game("a")
        let row = SpotlightRow.build(games: [a], enabledCards: [.addGame, .collection], order: [])
        XCTAssertEqual(row, [.card(.collection), .card(.addGame), .game(a.id)])
    }

    func testSavedOrderApplied() {
        let a = game("a"), b = game("b")
        let order = [SpotlightItem.game(b.id).key, SpotlightItem.card(.activity).key,
                     SpotlightItem.game(a.id).key, SpotlightItem.card(.surprise).key,
                     "game:\(UUID().uuidString)"]
        let row = SpotlightRow.build(games: [a, b], enabledCards: [.surprise, .activity], order: order)
        XCTAssertEqual(row, [.game(b.id), .card(.activity), .game(a.id), .card(.surprise)])
    }

    func testNewGameNotInOrderAppendsAfterOrdered() {
        let a = game("a"), b = game("b"), c = game("c")
        let order = [SpotlightItem.game(a.id).key, SpotlightItem.game(b.id).key]
        let row = SpotlightRow.build(games: [a, b, c], enabledCards: [.surprise], order: order)
        XCTAssertEqual(row, [.card(.surprise), .game(a.id), .game(b.id), .game(c.id)])
    }

    func testNewGameFollowsItsDefaultPredecessor() {
        let a = game("a"), b = game("b"), c = game("c")
        let order = [SpotlightItem.game(b.id).key, SpotlightItem.game(a.id).key]
        let row = SpotlightRow.build(games: [a, b, c], enabledCards: [], order: order)
        // c followed b in the default sequence, so it stays right after b.
        XCTAssertEqual(row, [.game(b.id), .game(c.id), .game(a.id)])
    }

    func testMoveClampsAtEdges() {
        let items: [SpotlightItem] = [.card(.surprise), .card(.activity), .card(.addGame)]
        XCTAssertEqual(SpotlightRow.moving(.card(.surprise), by: -1, in: items), items)
        XCTAssertEqual(SpotlightRow.moving(.card(.addGame), by: 1, in: items), items)
        XCTAssertEqual(SpotlightRow.moving(.card(.surprise), by: 1, in: items),
                       [.card(.activity), .card(.surprise), .card(.addGame)])
        XCTAssertEqual(SpotlightRow.moving(.card(.surprise), by: 99, in: items),
                       [.card(.activity), .card(.addGame), .card(.surprise)])
        XCTAssertEqual(SpotlightRow.moving(.game(UUID()), by: 1, in: items), items)
    }

    func testEmptyGamesStillReturnsCards() {
        let row = SpotlightRow.build(games: [], enabledCards: [.surprise, .addGame], order: [])
        XCTAssertEqual(row, [.card(.surprise), .card(.addGame)])
    }

    func testCardTitlesIconsAndKeys() {
        XCTAssertEqual(SpotlightCard.allCases.map(\.title), ["Collection", "Surprise me", "Activity", "Mods", "Add Game"])
        XCTAssertEqual(SpotlightCard.allCases.map(\.icon), [.collections, .casino, .timeline, .puzzle, .add])
        XCTAssertEqual(SpotlightItem.card(.addGame).key, "card:addGame")
        let id = UUID()
        XCTAssertEqual(SpotlightItem.game(id).key, "game:\(id.uuidString)")
    }

    func testSurpriseRespectsPoolAndExclusion() {
        let a = game("a"), b = game("b"), c = game("c", playable: false), h = game("h", hidden: true)
        let hist = FakeHistory(played: [a.id: Date()])
        var rng = SplitMix64(state: 42)
        for _ in 0..<50 {
            XCTAssertEqual(Surprise.pick(from: [a, b, c, h], pool: .installed, history: hist,
                                         excluding: a.id, random: &rng), b.id)
            let p = Surprise.pick(from: [a, b, c, h], pool: .notPlayed, history: hist,
                                  excluding: nil, random: &rng)
            XCTAssertTrue(p == b.id || p == c.id)
            let all = Surprise.pick(from: [a, b, c, h], pool: .all, history: hist,
                                    excluding: nil, random: &rng)
            XCTAssertNotEqual(all, h.id)
        }
    }

    func testSurpriseEmptyPoolReturnsNil() {
        var rng = SplitMix64(state: 1)
        let a = game("a")
        XCTAssertNil(Surprise.pick(from: [], pool: .all, history: NoPlayHistory(), excluding: nil, random: &rng))
        XCTAssertNil(Surprise.pick(from: [a], pool: .all, history: NoPlayHistory(), excluding: a.id, random: &rng))
        XCTAssertNil(Surprise.pick(from: [game("x", playable: false)], pool: .installed,
                                   history: NoPlayHistory(), excluding: nil, random: &rng))
        XCTAssertNil(Surprise.pick(from: [game("h", hidden: true)], pool: .all,
                                   history: NoPlayHistory(), excluding: nil, random: &rng))
    }
}

final class SpotlightRowMergeTests: XCTestCase {
    func testFilteredMoveKeepsHiddenSlots() {
        // Saved A…E as D,A,B,C,E; Installed shows A,C,E; C moved first.
        let merged = SpotlightRow.merging(visibleOrder: ["C", "A", "E"],
                                          into: ["D", "A", "B", "C", "E"])
        XCTAssertEqual(merged, ["D", "C", "B", "A", "E"])
    }

    func testAllFilterEqualsPlainOrder() {
        let full = ["A", "B", "C", "D"]
        XCTAssertEqual(SpotlightRow.merging(visibleOrder: ["B", "A", "C", "D"], into: full),
                       ["B", "A", "C", "D"])
    }

    func testUnknownKeysIgnored() {
        XCTAssertEqual(SpotlightRow.merging(visibleOrder: ["Z", "B", "A"], into: ["A", "X", "B"]),
                       ["B", "X", "A"])
    }
}

