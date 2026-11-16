import XCTest
@testable import NXLibraryCore

final class IGDBRatingTests: XCTestCase {
    private let credentials = IGDBCredentials(clientID: "fixtureClient123456", clientSecret: "fixtureSecret123456")!
    private let query = CriticRatingQuery(name: "Fixture™", platform: .switch)
    private let token = Data("{\"access_token\":\"fixtureToken\",\"expires_in\":3600,\"token_type\":\"bearer\"}".utf8)
    private let game = Data("""
    [{"id":10,"name":"Fixture","aggregated_rating":83.5,"aggregated_rating_count":12,
      "rating":99,"total_rating":96,"platforms":[130],"url":"https://www.igdb.com/games/fixture"}]
    """.utf8)
    private func response(_ request: URLRequest, _ data: Data, status: Int = 200) -> (Data, HTTPURLResponse) {
        (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func testPersonalCredentialsStayPrivateAndAreNotSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IGDBCredentialsStore(url: root.appendingPathComponent("igdb.json"))
        XCTAssertNil(store.load())
        try store.save(credentials)
        XCTAssertEqual(store.load(), credentials)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
        XCTAssertNil(IGDBCredentials(clientID: " bad id ", clientSecret: "secret"))
        XCTAssertNil(IGDBCredentials(clientID: "valid123", clientSecret: "Bearer token"))
        try store.remove()
        XCTAssertNil(store.load())
    }
    func testOnlyCriticAverageIsShownAndHasIGDBProvenance() throws {
        let rating = try XCTUnwrap(IGDBRatings.rating(in: game, query: query))
        XCTAssertEqual(rating.source, .igdb)
        XCTAssertEqual(rating.score, 83.5)
        XCTAssertEqual(rating.reviewCount, 12)
        XCTAssertEqual(rating.sourceURL.absoluteString, "https://www.igdb.com/games/fixture")
        XCTAssertEqual(rating.starFills.reduce(0,+), 4.175, accuracy: 0.0001)
        XCTAssertNil(rating.entityID)
        let userOnly = Data("[{\"id\":10,\"name\":\"Fixture\",\"rating\":99,\"rating_count\":100,\"platforms\":[130]}]".utf8)
        XCTAssertNil(try IGDBRatings.rating(in: userOnly, query: query))
    }
    func testExactTitleAliasAndPlatformWithoutSequelOrAmbiguity() throws {
        let otherPlatform = Data(String(decoding: game, as: UTF8.self).replacingOccurrences(of: "[130]", with: "[6]").utf8)
        XCTAssertNil(try IGDBRatings.rating(in: otherPlatform, query: query))
        XCTAssertNil(try IGDBRatings.rating(in: game, query: .init(name: "Fixture II", platform: .switch)))
        let duplicate = Data(("[" + String(decoding: game, as: UTF8.self).dropFirst().dropLast() + "," + String(decoding: game, as: UTF8.self).dropFirst().dropLast() + "]").utf8)
        XCTAssertNil(try IGDBRatings.rating(in: duplicate, query: query))
    }
    func testTokenAndAPIHostsAreIsolatedAndOfflineCacheSurvives() async throws {
        actor Requests {
            var items: [URLRequest] = []
            func add(_ request: URLRequest) { items.append(request) }
        }
        let requests = Requests(), token = token, game = game
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = IGDBRatingService(directory: root, transport: { request in
            await requests.add(request)
            let data = request.url!.host == "id.twitch.tv" ? token : game
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let first = await service.load(query, credentials: credentials)
        XCTAssertEqual(first.rating?.score, 83.5)
        let all = await requests.items
        XCTAssertEqual(all.map { $0.url!.host! }, ["id.twitch.tv", "api.igdb.com"])
        XCTAssertNil(all[0].url!.query)
        XCTAssertTrue(String(decoding: all[0].httpBody!, as: UTF8.self).contains("client_secret="))
        XCTAssertNil(all[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(all[1].value(forHTTPHeaderField: "Authorization"), "Bearer fixtureToken")
        XCTAssertFalse(String(decoding: all[1].httpBody!, as: UTF8.self).contains("fixtureSecret"))
        let offline = IGDBRatingService(directory: root, transport: { _ in throw URLError(.notConnectedToInternet) })
        let retained = await offline.load(query, credentials: credentials, now: Date().addingTimeInterval(8*86400))
        XCTAssertEqual(retained.rating, first.rating)
        XCTAssertTrue(retained.isStale)
    }
    func testRejectedCredentialsAreNotSuccessfulChecks() async throws {
        let service = IGDBRatingService(transport: { request in
            (Data("{\"message\":\"secret response must never be shown\"}".utf8),
             HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        })
        do { try await service.check(credentials); XCTFail("Rejected credentials must fail") }
        catch { XCTAssertEqual(error as? IGDBError, .rejected) }
    }
    func testSettingsSearchFindsIGDBInGeneralAPIServices() {
        XCTAssertEqual(SettingsCatalog.search("IGDB").first { $0.id == "igdb" }?.group, .apiServices)
    }

    func testExpiredOrRevokedTokenRenewsOnceAndConcurrentReadersShareWork() async throws {
        actor Calls {
            var tokens = 0, games = 0
            func next(isToken: Bool) -> Int {
                if isToken { tokens += 1; return tokens }
                games += 1; return games
            }
        }
        let calls = Calls(), token = token, game = game
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = IGDBRatingService(directory: root, transport: { request in
            let isToken = request.url!.host == "id.twitch.tv"
            let count = await calls.next(isToken: isToken)
            let status = !isToken && count == 1 ? 401 : 200
            return (isToken ? token : game, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        async let a = service.load(query, credentials: credentials)
        async let b = service.load(query, credentials: credentials)
        let values = await (a,b)
        XCTAssertEqual(values.0.rating?.score, 83.5)
        XCTAssertEqual(values.0.rating, values.1.rating)
        let tokens = await calls.tokens, games = await calls.games
        XCTAssertEqual(tokens, 2); XCTAssertEqual(games, 2)
    }

    func testCancellationStopsCredentialTransmissionAndDoesNotCacheAbsence() async throws {
        let started = expectation(description: "token started"), stopped = expectation(description: "token cancelled")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = IGDBRatingService(directory: root, transport: { _ in
            started.fulfill()
            do { try await Task.sleep(nanoseconds: 10_000_000_000); throw IGDBError.unreachable }
            catch { stopped.fulfill(); throw error }
        })
        let task = Task { await service.load(query, credentials: credentials) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        let result = await task.value
        XCTAssertNil(result.rating)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testWikidataRemainsTheFallbackWithFailedOrRemovedCredentials() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let wiki = CriticRatingService(directory: root.appendingPathComponent("wiki"), transport: { url in
            if url.query?.contains("wbsearchentities") == true {
                return Data("{\"search\":[{\"id\":\"Q10\",\"label\":\"Fixture\"}]}".utf8)
            }
            return Data("""
            {"entities":{"Q10":{"claims":{"P31":[{"mainsnak":{"datavalue":{"value":{"id":"Q7889"}}}}],
            "P444":[{"id":"Q10$s","mainsnak":{"datavalue":{"value":"78/100"}},
            "qualifiers":{"P447":[{"datavalue":{"value":{"id":"Q21039459"}}}],"P459":[{"datavalue":{"value":{"id":"Q114712322"}}}]},
            "references":[{"snaks":{"P248":[{"datavalue":{"value":{"id":"Q21039459"}}}]}}]}]}}}}
            """.utf8)
        })
        let primary = IGDBRatingService(directory: root.appendingPathComponent("igdb"), transport: { _ in throw URLError(.notConnectedToInternet) })
        let fallback = await wiki.preferred(query, credentials: credentials, igdb: primary)
        XCTAssertEqual(fallback.rating?.source, .openCritic)
        let removed = await wiki.preferred(query, credentials: nil, igdb: primary)
        XCTAssertEqual(removed.rating, fallback.rating)
    }

    func testSteamExternalMappingUsesItsSourceAndIDNotASimilarTitle() throws {
        let entry = """
        [{"uid":"42","external_game_source":{"name":"Steam"},"game":
        {"id":10,"name":"Official title","aggregated_rating":80,"aggregated_rating_count":3,"url":"https://www.igdb.com/games/official"}}]
        """
        XCTAssertEqual(try IGDBRatings.steamRating(in: Data(entry.utf8), appID: 42)?.score, 80)
        XCTAssertNil(try IGDBRatings.steamRating(in: Data(entry.utf8), appID: 99))
        XCTAssertNil(try IGDBRatings.steamRating(in: Data(entry.replacingOccurrences(of: "Steam", with: "GOG").utf8), appID: 42))
    }
}
