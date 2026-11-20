import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

/// A catalog written with a source this version does not know (a newer Arcane, or one without the Porting module)
/// opens, shows the games it knows and writes the others back untouched.
final class CatalogPreservationTests: XCTestCase {
    private let unknownGame: [String: Any] = [
        "integration": "crossover",
        "personalization": ["namespace": "crossover", "key": "crossover-7"],
        "data": ["id": "77777777-7777-7777-7777-777777777777", "name": "Bottle Game",
                 "sizeBytes": NSNumber(value: Int64.max), "rating": NSDecimalNumber(string: "3.25"),
                 "tags": ["a", ["b": NSNull()]], "installed": true],
    ]
    private let unknownSource: [String: Any] = ["integration": "crossover", "isEnabled": true, "bottles": ["Steam"]]

    private func todaysDocument() -> CatalogDocument {
        CatalogDocument(sources: [.init(integration: .nxnative, isEnabled: true), .init(integration: .steam)],
                        games: [.init(nxnative: CatalogTestSupport.completeLegacyGame())])
    }

    private func sortedEncoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]; return encoder
    }

    /// Today's catalog with the unknown game and source added, as a newer version would write it.
    private func catalogWithUnknownRecords() throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(todaysDocument())) as? [String: Any])
        json["games"] = (json["games"] as? [Any] ?? []) + [unknownGame]
        json["sources"] = (json["sources"] as? [Any] ?? []) + [unknownSource]
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func object(_ value: Any) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: value)) as? NSDictionary)
    }

    private func written(_ data: Data, integration: String, in key: String) throws -> NSDictionary {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let list = try XCTUnwrap(json[key] as? [[String: Any]])
        return try object(XCTUnwrap(list.first { $0["integration"] as? String == integration }))
    }

    func testJSONValuesRoundTripExactly() throws {
        let original = try JSONSerialization.data(withJSONObject: unknownGame)
        let value = try JSONDecoder().decode(CatalogJSON.self, from: original)
        let again = try sortedEncoder().encode(value)
        XCTAssertEqual(try object(JSONSerialization.jsonObject(with: again)), try object(unknownGame))
        XCTAssertTrue(String(decoding: again, as: UTF8.self).contains("9223372036854775807"))
        XCTAssertTrue(String(decoding: again, as: UTF8.self).contains("3.25"))
        XCTAssertEqual(value["integration"]?.stringValue, "crossover")
        XCTAssertEqual(try JSONDecoder().decode(CatalogJSON.self, from: Data("[0, 1, true, \"1\"]".utf8)),
                       .array([.number(0), .number(1), .bool(true), .string("1")]))
    }

    func testUnknownGameAndSourceAreKeptAndWrittenBack() throws {
        let document = try CatalogTestSupport.decoder().decode(CatalogDocument.self, from: catalogWithUnknownRecords())
        XCTAssertNoThrow(try document.validate())
        XCTAssertEqual(document.games.count, 1)
        XCTAssertEqual(document.sources.count, 2)
        XCTAssertEqual(document.preservedGames.count, 1)
        XCTAssertEqual(document.preservedSources.count, 1)
        let data = try sortedEncoder().encode(document)
        XCTAssertEqual(try written(data, integration: "crossover", in: "games"), try object(unknownGame))
        XCTAssertEqual(try written(data, integration: "crossover", in: "sources"), try object(unknownSource))
        XCTAssertEqual(try CatalogTestSupport.decoder().decode(CatalogDocument.self, from: data), document)
    }

    /// Without the Porting module's kind, a ported game is kept like any unknown record and written back the same.
    func testBaseKindsKeepSwitchGamesAsPreserved() throws {
        var document = todaysDocument()
        document.games.append(.init(steam: SteamCatalogGame(appID: 10, name: "Steam game")))
        let data = try sortedEncoder().encode(document)
        let base = try CatalogRecordKinds.base.decoder().decode(CatalogDocument.self, from: data)
        XCTAssertNoThrow(try base.validate())
        XCTAssertEqual(base.games.map(\.integration), [.steam])
        XCTAssertEqual(base.preservedGames.count, 1)
        XCTAssertEqual(base.preservedSources.count, 1)
        let again = try sortedEncoder().encode(base)
        XCTAssertEqual(try written(again, integration: "nxnative", in: "games"), try written(data, integration: "nxnative", in: "games"))
        XCTAssertEqual(try written(again, integration: "nxnative", in: "sources"), try written(data, integration: "nxnative", in: "sources"))
    }

    func testRecordsOfDifferentKindsAreNotEqual() {
        let ported = CatalogTestSupport.completeLegacyGame()
        var steam = SteamCatalogGame(id: ported.id, appID: 10, name: ported.name)
        steam.isFavorite = ported.isFavorite
        XCTAssertNotEqual(CatalogGame(nxnative: ported), CatalogGame(steam: steam))
        XCTAssertEqual(CatalogGame(nxnative: ported), CatalogGame(nxnative: ported))
    }

    func testStoreKeepsUnknownRecordsAcrossAChange() throws {
        let root = try SteamTestFixture.temporary(in: self).root
        try catalogWithUnknownRecords().write(to: root.appendingPathComponent("catalog.json"))
        let store = CatalogStore(directory: root)
        let loaded = try store.loadOrMigrate()
        XCTAssertEqual(loaded.games.count, 1)
        var draft = loaded
        draft.games[0].setFavorite(!loaded.games[0].isFavorite)
        _ = try store.save(draft, expectedRevision: loaded.revision)
        let data = try Data(contentsOf: root.appendingPathComponent("catalog.json"))
        XCTAssertEqual(try written(data, integration: "crossover", in: "games"), try object(unknownGame))
        XCTAssertEqual(try written(data, integration: "crossover", in: "sources"), try object(unknownSource))
        XCTAssertEqual(try store.loadOrMigrate().games[0].isFavorite, !loaded.games[0].isFavorite)
    }

    func testPreservedRecordWithAKnownGamesIDIsInvalid() throws {
        var game = unknownGame
        var data = try XCTUnwrap(game["data"] as? [String: Any])
        data["id"] = CatalogTestSupport.completeLegacyGame().id.uuidString
        game["data"] = data
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: catalogWithUnknownRecords()) as? [String: Any])
        json["games"] = Array((json["games"] as? [Any] ?? []).dropLast()) + [game]
        let document = try CatalogTestSupport.decoder().decode(CatalogDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try document.validate()) { XCTAssertEqual($0 as? CatalogModelError, .duplicateGameID) }
    }

    func testDuplicateUnknownSourceIsInvalid() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: catalogWithUnknownRecords()) as? [String: Any])
        json["sources"] = (json["sources"] as? [Any] ?? []) + [unknownSource]
        let document = try CatalogTestSupport.decoder().decode(CatalogDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try document.validate()) { XCTAssertEqual($0 as? CatalogModelError, .invalidRecord) }
    }

    func testPreservedGameMustBeAnObjectWithData() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: catalogWithUnknownRecords()) as? [String: Any])
        json["games"] = Array((json["games"] as? [Any] ?? []).dropLast()) + [["integration": "crossover", "data": "text"]]
        let document = try CatalogTestSupport.decoder().decode(CatalogDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try document.validate()) { XCTAssertEqual($0 as? CatalogModelError, .invalidRecord) }
    }

    /// Nothing changes for a catalog with only known sources: the same bytes as before the change.
    func testCatalogWithoutUnknownRecordsIsWrittenAsToday() throws {
        let document = todaysDocument()
        let today = TodaysCatalog(schemaVersion: document.schemaVersion, revision: document.revision,
                                  legacyOrigin: document.legacyOrigin, sources: document.sources, games: document.games)
        XCTAssertEqual(String(decoding: try sortedEncoder().encode(document), as: UTF8.self),
                       String(decoding: try sortedEncoder().encode(today), as: UTF8.self))
        XCTAssertTrue(document.preservedGames.isEmpty)
    }
}

/// The catalog's shape as schema 1 writes it, with the encoder Swift synthesizes: the reference for "as today".
private struct TodaysCatalog: Encodable {
    let schemaVersion: Int
    let revision: UUID
    let legacyOrigin: CatalogLegacyOrigin
    let sources: [CatalogSourceConfiguration]
    let games: [CatalogGame]
}
