import XCTest
@testable import NXLibraryCore

final class NintendoStoreMetadataTests: XCTestCase {
    private final class FakeClient: NintendoStoreHTTPClient {
        var responses: [String: Data] = [:]
        var requested: [String] = []

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let url = request.url?.absoluteString ?? ""
            requested.append(url)
            guard let data = responses.first(where: { url.contains($0.key) })?.value else {
                throw URLError(.badServerResponse)
            }
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200,
                                          httpVersion: nil, headerFields: nil)!)
        }
    }

    private func game(name: String, titleId: String) -> PortedGame {
        PortedGame(name: name, url: URL(fileURLWithPath: "/tmp/\(name).app"),
                   platform: .macApp, sizeBytes: 1, modificationDate: Date(),
                   titleId: titleId)
    }

    private func cacheDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXStore-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testUsesTheLegacyCatalogWithoutFetchingTheProductPage() async throws {
        let client = FakeClient()
        client.responses["ncom_game_en_us/query"] = Data("""
        {"hits":[{"title":"The Legend of Zelda™: Breath of the Wild",
          "nsuid":"70010000000025",
          "description":"Forget everything you know about The Legend of Zelda games. Step into a world of discovery.",
          "developers":["Nintendo"],"publishers":["Nintendo"],
          "genres":["Adventure","Action"],
          "releaseDateDisplay":"2017-03-03T08:00:00.000Z",
          "url":"/games/detail/the-legend-of-zelda-breath-of-the-wild-switch/",
          "boxart":"https://assets.nintendo.com/boxart.jpg",
          "horizontalHeaderImage":"https://assets.nintendo.com/hero.jpg",
          "platform":"Nintendo Switch"}]}
        """.utf8)
        let service = NintendoStoreMetadataService(client: client, cacheDirectory: cacheDirectory())
        let metadata = try await service.metadata(for: game(name: "The Legend of Zelda: Breath of the Wild",
                                                           titleId: "01007EF00011E000"))
        XCTAssertEqual(metadata.name, "The Legend of Zelda™: Breath of the Wild")
        XCTAssertTrue(metadata.description.contains("Forget everything"))
        XCTAssertEqual(metadata.genres, ["Adventure", "Action"])
        XCTAssertEqual(metadata.publishers, ["Nintendo"])
        XCTAssertEqual(metadata.releaseYear, "2017")
        XCTAssertEqual(metadata.storeURL.absoluteString,
                       "https://www.nintendo.com/games/detail/the-legend-of-zelda-breath-of-the-wild-switch/")
        XCTAssertFalse(client.requested.contains { $0.contains("nintendo.com/us/store/products") })
    }

    func testFallsBackToTheProductPageForNewerGames() async throws {
        let client = FakeClient()
        client.responses["ncom_game_en_us/query"] = Data(#"{"hits":[]}"#.utf8)
        client.responses["store_all_products_en_us/query"] = Data("""
        {"hits":[{"title":"Super Mario Bros.™ Wonder","nsuid":"70010000068688",
          "platform":"Nintendo Switch","topLevelCategory":"Games",
          "url":"/us/store/products/super-mario-bros-wonder-switch/"}]}
        """.utf8)
        let page = """
        <html><script id="__NEXT_DATA__" type="application/json">
        {"props":{"pageProps":{
          "initialApolloState":{
            "Product:{\\"sku\\":\\"7100068688\\"}":{
              "name":"Super Mario Bros.™ Wonder",
              "description":"Classic Mario side-scrolling gameplay is turned on its head with Wonder Flowers.",
              "tags":{"genres":[{"label":"Action"}]},
              "productImage":{"url":"https://assets.nintendo.com/wonder.jpg"},
              "releaseDate":"2023-10-20T00:00:00.000Z"
            }
          },
          "linkedData":[{"publisher":{"name":"Nintendo"}}]
        }}}
        </script></html>
        """
        client.responses["nintendo.com/us/store/products/super-mario-bros-wonder-switch"] = Data(page.utf8)
        let service = NintendoStoreMetadataService(client: client, cacheDirectory: cacheDirectory())
        let metadata = try await service.metadata(for: game(name: "Super Mario Bros. Wonder",
                                                           titleId: "010015100B514000"))
        XCTAssertEqual(metadata.name, "Super Mario Bros.™ Wonder")
        XCTAssertTrue(metadata.description.contains("Wonder Flowers"))
        XCTAssertEqual(metadata.genres, ["Action"])
        XCTAssertEqual(metadata.publishers, ["Nintendo"])
        XCTAssertEqual(metadata.releaseYear, "2023")
        XCTAssertEqual(metadata.storeURL.absoluteString,
                       "https://www.nintendo.com/us/store/products/super-mario-bros-wonder-switch/")
        XCTAssertEqual(metadata.headerImageURL?.absoluteString, "https://assets.nintendo.com/wonder.jpg")
        XCTAssertNil(metadata.imageURL)
    }

    func testCachesTheResult() async throws {
        let client = FakeClient()
        client.responses["ncom_game_en_us/query"] = Data("""
        {"hits":[{"title":"Super Mario Odyssey™","nsuid":"70010000001130",
          "description":"Explore incredible places far from the Mushroom Kingdom.",
          "developers":["Nintendo"],"publishers":["Nintendo"],"genres":["Platformer"],
          "releaseDateDisplay":"2017-10-27T07:00:00.000Z",
          "url":"/games/detail/super-mario-odyssey-switch/",
          "platform":"Nintendo Switch"}]}
        """.utf8)
        let cache = cacheDirectory()
        let service = NintendoStoreMetadataService(client: client, cacheDirectory: cache)
        _ = try await service.metadata(for: game(name: "Super Mario Odyssey", titleId: "0100000000010000"))
        XCTAssertNotNil(service.cached(for: "0100000000010000"))
        let second = NintendoStoreMetadataService(client: FakeClient(), cacheDirectory: cache)
        let cached = try await second.metadata(for: game(name: "Super Mario Odyssey", titleId: "0100000000010000"))
        XCTAssertTrue(cached.description.contains("Mushroom Kingdom"))
    }

    func testCacheSizeAndClear() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXMeta-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("a.json"))
        try Data("{}".utf8).write(to: dir.appendingPathComponent("b.json"))
        let service = NintendoStoreMetadataService(client: URLSessionNintendoStoreClient(),
                                                   cacheDirectory: dir)
        XCTAssertGreaterThan(service.cacheSize(), 0)
        service.clearCache()
        XCTAssertEqual(service.cacheSize(), 0)
    }

    func testNoResultThrows() async throws {
        let client = FakeClient()
        client.responses["ncom_game_en_us/query"] = Data(#"{"hits":[]}"#.utf8)
        client.responses["store_all_products_en_us/query"] = Data(#"{"hits":[]}"#.utf8)
        let service = NintendoStoreMetadataService(client: client, cacheDirectory: cacheDirectory())
        do {
            _ = try await service.metadata(for: game(name: "Unknown Game", titleId: "0100000000000000"))
            XCTFail("expected notFound")
        } catch let error as NintendoStoreError {
            XCTAssertEqual(error, .notFound)
        }
    }

    // MARK: - titledb details

    private let tid = "01007EF00011E000"

    private var titleDBJSON: Data {
        let shots = (1...6).map { "\"http://api.nlib.cc/nx/01007EF00011E000/screen/\($0)\"" }.joined(separator: ",")
        return Data("""
        {"id":"01007EF00011E000","name":"Zelda","screens":{"count":6,"screenshots":[\(shots)]},"releaseDate":"2017-03-03","developer":null,"category":["Adventure","Action","RPG","Other"]}
        """.utf8)
    }

    private func titleDBOnlyClient(_ json: Data) -> FakeClient {
        let client = FakeClient()
        client.responses["ncom_game_en_us/query"] = Data(#"{"hits":[]}"#.utf8)
        client.responses["store_all_products_en_us/query"] = Data(#"{"hits":[]}"#.utf8)
        client.responses["api.nlib.cc/nx/\(tid)"] = json
        return client
    }

    func testParsesSixScreenshotsAsHTTPS() async throws {
        let service = NintendoStoreMetadataService(client: titleDBOnlyClient(titleDBJSON), cacheDirectory: cacheDirectory())
        let meta = try await service.metadata(for: game(name: "Zelda", titleId: tid))
        XCTAssertEqual(meta.screenshotURLs.count, 6)
        XCTAssertTrue(meta.screenshotURLs.allSatisfy { $0.scheme == "https" && $0.host == "api.nlib.cc" })
        XCTAssertEqual(meta.releaseDate, "2017-03-03")
    }

    func testCategoryBecomesGenresWithoutOther() async throws {
        let service = NintendoStoreMetadataService(client: titleDBOnlyClient(titleDBJSON), cacheDirectory: cacheDirectory())
        let meta = try await service.metadata(for: game(name: "Zelda", titleId: tid))
        XCTAssertEqual(meta.genres, ["Adventure", "Action", "RPG"])
        XCTAssertEqual(meta.developers, [])
    }

    func testStorePathWinsAndTitleDBOnlyFillsScreenshots() async throws {
        let client = FakeClient()
        client.responses["ncom_game_en_us/query"] = Data("""
        {"hits":[{"title":"Zelda","description":"A long enough description.","developers":["Nintendo"],
          "genres":["Adventure"],"releaseDateDisplay":"2017-03-03T08:00:00.000Z",
          "url":"/games/detail/z/","platform":"Nintendo Switch"}]}
        """.utf8)
        client.responses["api.nlib.cc/nx/\(tid)"] = titleDBJSON
        let service = NintendoStoreMetadataService(client: client, cacheDirectory: cacheDirectory())
        let meta = try await service.metadata(for: game(name: "Zelda", titleId: tid))
        XCTAssertEqual(meta.genres, ["Adventure"])
        XCTAssertEqual(meta.developers, ["Nintendo"])
        XCTAssertEqual(meta.screenshotURLs.count, 6)
        XCTAssertEqual(client.requested.filter { $0.contains("api.nlib.cc") }.count, 1)
    }

    func testMissingScreensGivesEmptyArray() async throws {
        let json = Data(#"{"id":"01007EF00011E000","name":"Zelda","releaseDate":20170303}"#.utf8)
        let service = NintendoStoreMetadataService(client: titleDBOnlyClient(json), cacheDirectory: cacheDirectory())
        let meta = try await service.metadata(for: game(name: "Zelda", titleId: tid))
        XCTAssertEqual(meta.screenshotURLs, [])
        XCTAssertEqual(meta.releaseDate, "2017-03-03")
    }

    func testOldCacheWithoutScreenshotsDecodes() throws {
        let json = Data("""
        {"titleId":"A","name":"N","description":"D","developers":[],"publishers":[],"genres":[],
         "storeURL":"https://www.nintendo.com","fetchedAt":0}
        """.utf8)
        let meta = try JSONDecoder().decode(NintendoStoreMetadata.self, from: json)
        XCTAssertEqual(meta.screenshotURLs, [])
    }

    func testOfflineWithoutCacheThrowsAndNoTitleIdSkipsTitledb() async throws {
        let client = FakeClient() // every request throws
        let service = NintendoStoreMetadataService(client: client, cacheDirectory: cacheDirectory())
        do {
            _ = try await service.metadata(for: game(name: "Zelda", titleId: tid))
            XCTFail("expected throw")
        } catch {}

        let client2 = FakeClient()
        client2.responses["ncom_game_en_us/query"] = Data(#"{"hits":[]}"#.utf8)
        client2.responses["store_all_products_en_us/query"] = Data(#"{"hits":[]}"#.utf8)
        let service2 = NintendoStoreMetadataService(client: client2, cacheDirectory: cacheDirectory())
        let noID = PortedGame(name: "Zelda", url: URL(fileURLWithPath: "/tmp/z.app"), platform: .macApp,
                              sizeBytes: 1, modificationDate: Date(), titleId: nil)
        do {
            _ = try await service2.metadata(for: noID)
            XCTFail("expected throw")
        } catch {}
        XCTAssertFalse(client2.requested.contains { $0.contains("api.nlib.cc") })
    }
}
