import XCTest
@testable import NXLibraryCore

final class GameBananaMatchTests: XCTestCase {
    private func game(_ id: Int, _ name: String) -> GameBananaGame { GameBananaGame(id: id, name: name) }

    func testNormalizedFoldsMarksAndPunctuation() {
        XCTAssertEqual(GameBananaMatch.normalized("Pokémon™ Legends: Arceus"), GameBananaMatch.normalized("pokemon legends arceus"))
        XCTAssertEqual(GameBananaMatch.normalized("Mario & Luigi"), GameBananaMatch.normalized("Mario and Luigi"))
        XCTAssertEqual(GameBananaMatch.normalized("  Super   Mario Odyssey "), "super mario odyssey")
    }

    func testExactNameMatches() {
        let decision = GameBananaMatch.decide(names: ["Super Mario Odyssey"],
                                              results: [game(6376, "Super Mario Odyssey"), game(9, "Super Mario Odyssey 2")])
        XCTAssertEqual(decision, .matched(game(6376, "Super Mario Odyssey")))
    }

    func testSwitchEntryWinsOverOtherPlatform() {
        let wiiu = game(5866, "The Legend of Zelda: Breath of the Wild (WiiU)")
        let nx = game(6386, "The Legend of Zelda: Breath of the Wild (Switch)")
        let names = ["The Legend of Zelda: Breath of the Wild"]
        XCTAssertEqual(GameBananaMatch.decide(names: names, results: [wiiu, nx]), .matched(nx))
        XCTAssertEqual(GameBananaMatch.decide(names: names, results: [wiiu]), .ask([wiiu]))
    }

    func testNearNamesAsk() {
        let totk = game(7617, "The Legend of Zelda: Tears of the Kingdom")
        XCTAssertEqual(GameBananaMatch.decide(names: ["Zelda TOTK"], results: [totk]), .ask([totk]))
        let many = (1...8).map { game($0, "Game \($0)") }
        guard case .ask(let candidates) = GameBananaMatch.decide(names: ["Other"], results: many) else {
            return XCTFail("expected ask")
        }
        XCTAssertEqual(candidates.count, 5)
    }

    func testOtherPlatformCandidatesComeLast() {
        let wiiu = game(1, "Zelda (WiiU)")
        let plain = game(2, "Zelda Collection")
        XCTAssertEqual(GameBananaMatch.decide(names: ["Zelda HD"], results: [wiiu, plain]), .ask([plain, wiiu]))
    }

    func testEmptyResultsAreNone() {
        XCTAssertEqual(GameBananaMatch.decide(names: ["Anything"], results: []), .none)
    }

    func testStoreRemembersAndForgets() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("GBMatch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("gamebanana/matches.json")
        let store = GameBananaMatchStore(file: file)
        let choice = GameBananaChoice.game(id: 7617, name: "Tears of the Kingdom",
                                           profileURL: URL(string: "https://gamebanana.com/games/7617")!)
        try store.set(choice, titleID: "0100f2c0115b6000")
        XCTAssertEqual(store.choice(titleID: "0100F2C0115B6000"), choice)
        XCTAssertEqual(GameBananaMatchStore(file: file).choice(titleID: "0100f2c0115b6000"), choice)
        try store.set(.noPage, titleID: "0100F2C0115B6000")
        XCTAssertEqual(store.choice(titleID: "0100F2C0115B6000"), .noPage)
        try store.set(nil, titleID: "0100F2C0115B6000")
        XCTAssertNil(store.choice(titleID: "0100F2C0115B6000"))
    }
}
