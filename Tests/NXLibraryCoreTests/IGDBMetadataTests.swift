import XCTest
@testable import NXLibraryCore

final class IGDBMetadataTests: XCTestCase {
    private let query = CriticRatingQuery(name: "Fixture™", platform: .switch2)
    private let credentials = IGDBCredentials(clientID: "fixtureClient123456", clientSecret: "fixtureSecret123456")!
    private let token = Data(#"{"access_token":"fixtureToken","expires_in":3600,"token_type":"bearer"}"#.utf8)
    private let game = Data("""
    [{"id":10,"name":"Fixture","platforms":[508],"url":"https://www.igdb.com/games/fixture",
      "summary":" A description. ","genres":[{"name":"Adventure"},{"name":"Puzzle"}],
      "involved_companies":[{"company":{"name":"Developer"},"developer":true,"publisher":false},
        {"company":{"name":"Publisher"},"developer":false,"publisher":true},
        {"company":{"name":"Support"},"developer":false,"publisher":false}],
      "release_dates":[{"platform":130,"date":1704412800,"date_format":{"format":"YYYYMMDD"}},
        {"platform":508,"date":1793836800,"date_format":{"format":"YYYYMMDD"}}]}]
    """.utf8)

    func testFieldsRolesAndExactPlatformDateBecomeIndividualPreviewOptions() throws {
        let result = try IGDBMetadataParser.result(in: game, query: query)
        let metadata = try XCTUnwrap(result.metadata)
        XCTAssertEqual(metadata.id, 10)
        XCTAssertEqual(metadata.option(for: .description)?.value, "A description.")
        XCTAssertEqual(metadata.option(for: .description)?.source, "IGDB")
        XCTAssertEqual(metadata.option(for: .genres)?.value, "Adventure, Puzzle")
        XCTAssertEqual(metadata.option(for: .developer)?.value, "Developer")
        XCTAssertEqual(metadata.option(for: .publisher)?.value, "Publisher")
        XCTAssertEqual(metadata.option(for: .releaseDate)?.value, "2026-11-05")
        XCTAssertEqual(try JSONDecoder().decode(IGDBMetadata.self, from: JSONEncoder().encode(metadata)), metadata)
    }

    func testPartialDatesForeignPlatformsAndOtherEditionsAreNotInvented() throws {
        let partial = Data(String(decoding: game, as: UTF8.self).replacingOccurrences(of: "YYYYMMDD", with: "YYYYMM").utf8)
        XCTAssertNil(try IGDBMetadataParser.result(in: partial, query: query).metadata?.option(for: .releaseDate))
        let foreign = CriticRatingQuery(name: "Fixture", platform: .switch)
        XCTAssertEqual(try IGDBMetadataParser.result(in: game, query: foreign).issue, .notFound)
        XCTAssertEqual(try IGDBMetadataParser.result(in: game, query: .init(name: "Fixture II", platform: .switch2)).issue, .notFound)
        let duplicate = Data(("[" + String(decoding: game, as: UTF8.self).dropFirst().dropLast() + "," + String(decoding: game, as: UTF8.self).dropFirst().dropLast() + "]").utf8)
        XCTAssertEqual(try IGDBMetadataParser.result(in: duplicate, query: query).issue, .ambiguous)
        let empty = Data(#"[{"id":10,"name":"Fixture","platforms":[508],"url":"https://www.igdb.com/games/fixture"}]"#.utf8)
        XCTAssertNil(try IGDBMetadataParser.result(in: empty, query: query).metadata?.option(for: .description))
        XCTAssertThrowsError(try IGDBMetadataParser.result(in: Data("{}".utf8), query: query))
    }

    func testSteamIdentityUsesTheExternalIDWithoutBorrowingAPortsReleaseDate() throws {
        let nested = String(decoding: game, as: UTF8.self).dropFirst().dropLast()
        let external = Data(("[{\"uid\":\"42\",\"external_game_source\":{\"name\":\"Steam\"},\"game\":" + nested + "}]").utf8)
        let steam = CriticRatingQuery(name: "Personal name", platform: .mac, steamAppID: 42)
        let result = try IGDBMetadataParser.steamResult(in: external, query: steam)
        XCTAssertEqual(result.metadata?.option(for: .description)?.value, "A description.")
        XCTAssertNil(result.metadata?.option(for: .releaseDate))
        XCTAssertEqual(try IGDBMetadataParser.steamResult(in: external, query: .init(name: "Fixture", platform: .mac, steamAppID: 99)).issue, .notFound)
    }

    func testCacheRemainsAvailableOfflineAndNeverChangesPersonalPicks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let token = token, game = game
        let service = IGDBMetadataService(directory: root, transport: { request in
            if request.url!.host == "api.igdb.com" {
                let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
                XCTAssertTrue(body.contains("involved_companies.developer"))
                XCTAssertTrue(body.contains("release_dates.date_format.format"))
            }
            return (request.url!.host == "id.twitch.tv" ? token : game,
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let found = await service.load(query, credentials: credentials)
        XCTAssertEqual(found.metadata?.id, 10)
        let offline = IGDBMetadataService(directory: root, transport: { _ in throw URLError(.notConnectedToInternet) })
        let retained = await offline.load(query, credentials: credentials, now: Date().addingTimeInterval(8 * 86400))
        XCTAssertEqual(retained.metadata, found.metadata)
        XCTAssertTrue(retained.isStale)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("metadata-picks.json").path))
    }

    func testCancellationDoesNotSaveAMissingMatch() async throws {
        let started = expectation(description: "request starts"), stopped = expectation(description: "request stops")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = IGDBMetadataService(directory: root, transport: { _ in
            started.fulfill()
            do { try await Task.sleep(nanoseconds: 10_000_000_000); throw URLError(.timedOut) }
            catch { stopped.fulfill(); throw error }
        })
        let query = query, credentials = credentials
        let task = Task { await service.load(query, credentials: credentials) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        let result = await task.value
        XCTAssertNil(result.metadata)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testFailureDoesNotBecomeANegativeCacheAndCanBeRetried() async throws {
        actor Calls {
            var games = 0
            func next() -> Int { games += 1; return games }
        }
        let calls = Calls(), token = token, game = game
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = IGDBMetadataService(directory: root, transport: { request in
            if request.url!.host == "id.twitch.tv" {
                return (token, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let count = await calls.next()
            return (count == 1 ? Data("private server details".utf8) : game,
                    HTTPURLResponse(url: request.url!, statusCode: count == 1 ? 503 : 200, httpVersion: nil, headerFields: nil)!)
        })
        let failed = await service.load(query, credentials: credentials)
        XCTAssertEqual(failed.issue, .unavailable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let retried = await service.load(query, credentials: credentials)
        XCTAssertEqual(retried.metadata?.id, 10)
    }

    func testSharedClientSerializesDifferentLookupsAndReusesOneToken() async throws {
        actor Calls {
            var tokens = 0, active = 0, maximum = 0
            func begin(_ token: Bool) {
                if token { tokens += 1 }
                active += 1; maximum = max(maximum, active)
            }
            func end() { active -= 1 }
        }
        let calls = Calls(), token = token
        let client = IGDBClient(transport: { request in
            let isToken = request.url!.host == "id.twitch.tv"
            await calls.begin(isToken)
            try await Task.sleep(nanoseconds: 10_000_000)
            await calls.end()
            return (isToken ? token : Data("[]".utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        async let games = client.request("games", body: "fields id; limit 1;", credentials: credentials)
        async let external = client.request("external_games", body: "fields id; limit 1;", credentials: credentials)
        _ = try await (games, external)
        let tokens = await calls.tokens, maximum = await calls.maximum
        XCTAssertEqual(tokens, 1)
        XCTAssertEqual(maximum, 1)
    }
}
