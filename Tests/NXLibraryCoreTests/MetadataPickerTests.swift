import XCTest
@testable import NXLibraryCore

final class MetadataPickerTests: XCTestCase {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MetaPicks-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private let store = NintendoStoreMetadata(
        titleId: "0100F2C0115B6000", name: "The Legend of Zelda™: Tears of the Kingdom",
        description: "Store text.", developers: ["Nintendo EPD"], publishers: ["Nintendo"],
        genres: ["Action", "Adventure"], releaseDate: "2023-05-12",
        storeURL: URL(string: "https://www.nintendo.com/x")!, imageURL: nil, headerImageURL: nil,
        nsuid: nil, fetchedAt: Date())

    private let tdb = GameTDBEntry(id: "AAAAB", title: "The Legend of Zelda: Tears of the Kingdom", region: "ALL",
                                   synopsis: "GameTDB text.", developer: "Nintendo", publisher: "Nintendo",
                                   releaseDate: "2023-05-12", genres: ["action", "adventure", "open world"])

    func testTitleDBInfoReadsTextFields() throws {
        let json = """
        {"name":"Zelda","description":"Title DB text.","publisher":"Nintendo","developer":null,
         "releaseDate":20230512,"category":["Adventure","Action"],"icon":null,"banner":null}
        """
        let info = try TitleDBInfo.decode(Data(json.utf8))
        XCTAssertEqual(info.description, "Title DB text.")
        XCTAssertEqual(info.publisher, "Nintendo")
        XCTAssertNil(info.developer)
        XCTAssertEqual(info.releaseDate, "2023-05-12")
        XCTAssertEqual(info.categories, ["Adventure", "Action"])
        let text = try TitleDBInfo.decode(Data(#"{"releaseDate":"2017-03-03"}"#.utf8))
        XCTAssertEqual(text.releaseDate, "2017-03-03")
    }

    func testOptionsListEachSourceOnceAndSkipEmpty() {
        let titleDB = TitleDBInfo(name: nil, icon: nil, banner: nil, screenshots: [], description: "Title DB text.",
                                  developer: nil, publisher: "Nintendo", releaseDate: "2023-05-12",
                                  categories: ["Adventure", "Action"])
        let descriptions = MetadataOptions.list(for: .description, store: store, titleDB: titleDB, gameTDB: [tdb])
        XCTAssertEqual(descriptions.map(\.source), ["Nintendo store", "Title DB", "GameTDB"])
        XCTAssertEqual(descriptions.map(\.value), ["Store text.", "Title DB text.", "GameTDB text."])

        // Same publisher everywhere: offered once, under the first source.
        let publishers = MetadataOptions.list(for: .publisher, store: store, titleDB: titleDB, gameTDB: [tdb])
        XCTAssertEqual(publishers.map(\.source), ["Nintendo store"])

        let developers = MetadataOptions.list(for: .developer, store: store, titleDB: titleDB, gameTDB: [tdb])
        XCTAssertEqual(developers.map(\.value), ["Nintendo EPD", "Nintendo"])

        let genres = MetadataOptions.list(for: .genres, store: store, titleDB: titleDB, gameTDB: [tdb])
        XCTAssertEqual(genres.map(\.value), ["Action, Adventure", "Adventure, Action", "Action, Adventure, Open World"])

        XCTAssertEqual(MetadataOptions.list(for: .releaseDate, store: nil, titleDB: nil, gameTDB: []), [])
    }

    func testPicksApplyPersistAndRemove() throws {
        let dir = tempDir()
        let picks = MetadataPicks(directory: dir)
        XCTAssertEqual(picks.applied(to: store, titleID: store.titleId), store)

        picks.set("Your own text.", titleID: store.titleId, field: .description)
        picks.set("Action, Open World", titleID: store.titleId, field: .genres)
        picks.set("Monolith Soft", titleID: store.titleId, field: .developer)
        picks.set("2023-05-11", titleID: store.titleId, field: .releaseDate)
        XCTAssertEqual(picks.revision, 4)

        let reread = MetadataPicks(directory: dir)
        let applied = reread.applied(to: store, titleID: store.titleId)
        XCTAssertEqual(applied.description, "Your own text.")
        XCTAssertEqual(applied.genres, ["Action", "Open World"])
        XCTAssertEqual(applied.developers, ["Monolith Soft"])
        XCTAssertEqual(applied.publishers, ["Nintendo"], "fields without a pick keep the store's value")
        XCTAssertEqual(applied.releaseDate, "2023-05-11")
        XCTAssertEqual(reread.value(titleID: store.titleId, field: .developer), "Monolith Soft")

        reread.remove(titleID: store.titleId, field: .developer)
        XCTAssertEqual(MetadataPicks(directory: dir).applied(to: store, titleID: store.titleId).developers, ["Nintendo EPD"])

        // A blank value is no pick.
        reread.set("   ", titleID: store.titleId, field: .publisher)
        XCTAssertNil(reread.value(titleID: store.titleId, field: .publisher))
    }

    func testFieldsAreTheSpecsFive() {
        XCTAssertEqual(MetadataField.allCases.map(\.title),
                       ["Description", "Genres", "Developer", "Publisher", "Release date"])
    }
}
