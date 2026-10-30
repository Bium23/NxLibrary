import XCTest
@testable import NXLibraryCore

final class GameTDBTests: XCTestCase {
    // Trimmed from switchtdb.xml (LANG=EN): the shapes the parser must read and skip.
    private let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <datafile>
      <SwitchTDB version="20261030101455" filter="EN" games="3"/>
      <genres><maingenre name="theme"><loc lang="FR">thème</loc></maingenre></genres>
      <game name="The Legend of Zelda: Breath of the Wild (EN,FR)">
        <id>AAAAA</id><type>Switch</type><region>ALL</region>
        <locale lang="EN"><title>The Legend of Zelda: Breath of the Wild</title><synopsis>Step into a world.</synopsis></locale>
        <locale lang="FR"><title>Zelda FR</title><synopsis/></locale>
        <developer>Nintendo</developer><publisher>Nintendo</publisher>
        <date year="2017" month="3" day="3"/><genre>action,adventure</genre>
        <rom version="0" name="x.switch" size="1"/>
      </game>
      <game name="Super Mario Odyssey (EN)">
        <id>AACCA</id><type>Switch</type><region>NTSC-U</region>
        <locale lang="EN"><title>Super Mario Odyssey</title><synopsis/></locale>
        <developer>Nintendo EPD</developer><publisher>Nintendo</publisher>
        <date year="2017" month="10" day="27"/><genre>platformer</genre>
      </game>
      <game name="Super Mario Odyssey (JA)">
        <id>AACCB</id><type>Switch</type><region>NTSC-J</region>
        <locale lang="EN"><title>Super Mario Odyssey</title></locale>
      </game>
    </datafile>
    """

    private func entries() throws -> [GameTDBEntry] {
        try GameTDB.parse(Data(xml.utf8))
    }

    func testParseReadsEnglishFields() throws {
        let all = try entries()
        XCTAssertEqual(all.map(\.id), ["AAAAA", "AACCA", "AACCB"])
        let zelda = all[0]
        XCTAssertEqual(zelda.title, "The Legend of Zelda: Breath of the Wild")
        XCTAssertEqual(zelda.region, "ALL")
        XCTAssertEqual(zelda.synopsis, "Step into a world.")
        XCTAssertEqual(zelda.developer, "Nintendo")
        XCTAssertEqual(zelda.publisher, "Nintendo")
        XCTAssertEqual(zelda.releaseDate, "2017-03-03")
        XCTAssertEqual(zelda.genres, ["action", "adventure"])
        XCTAssertNil(all[1].synopsis)
        XCTAssertThrowsError(try GameTDB.parse(Data("<datafile><game>".utf8)))
    }

    func testNormalize() {
        XCTAssertEqual(GameTDB.normalize("The Legend of Zelda™: Breath of the Wild"),
                       "the legend of zelda breath of the wild")
        XCTAssertEqual(GameTDB.normalize("  Mario + Rabbids® Kingdom Battle "), "mario rabbids kingdom battle")
        XCTAssertEqual(GameTDB.normalize("Pokémon™ Sword & Shield"), "pokémon sword and shield")
    }

    func testExactMatchPrefersWideRegions() throws {
        let all = try entries()
        XCTAssertEqual(GameTDB.exactMatch(for: "The Legend of Zelda™: Breath of the Wild", in: all)?.id, "AAAAA")
        XCTAssertEqual(GameTDB.exactMatch(for: "SUPER MARIO ODYSSEY", in: all)?.id, "AACCA")
        XCTAssertNil(GameTDB.exactMatch(for: "Super Mario", in: all))
    }

    func testCandidatesRankExactThenOverlap() throws {
        let all = try entries()
        XCTAssertEqual(GameTDB.candidates(for: "Super Mario Odyssey", in: all).map(\.id), ["AACCA", "AACCB"])
        XCTAssertEqual(GameTDB.candidates(for: "Mario Odyssey", in: all).map(\.id), ["AACCA", "AACCB"])
        XCTAssertEqual(GameTDB.candidates(for: "Breath of the Wild", in: all).map(\.id), ["AAAAA"])
        XCTAssertEqual(GameTDB.candidates(for: "Metroid Dread", in: all), [])
    }

    func testCoverURLsWalkRegions() {
        let urls = GameTDB.coverURLs(id: "AAAAA").map(\.absoluteString)
        XCTAssertEqual(urls.first, "https://art.gametdb.com/switch/coverHQ/US/AAAAA.jpg")
        XCTAssertEqual(urls[1], "https://art.gametdb.com/switch/coverHQ/EN/AAAAA.jpg")
        XCTAssertTrue(urls.contains("https://art.gametdb.com/switch/coverHQ/JA/AAAAA.jpg"))
        XCTAssertEqual(GameTDB.coverURLs(id: "../x"), [])
    }

    func testStoreSavesLoadsAndAges() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("GameTDB-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = GameTDBStore(directory: dir)
        XCTAssertNil(store.load())
        XCTAssertTrue(store.isStale(now: Date()))

        try store.save(try entries())
        XCTAssertEqual(store.load()?.count, 3)
        XCTAssertFalse(store.isStale(now: Date()))
        XCTAssertTrue(store.isStale(now: Date().addingTimeInterval(31 * 24 * 3600)))
    }
}
