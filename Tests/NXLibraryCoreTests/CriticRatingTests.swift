import XCTest
@testable import NXLibraryCore

final class CriticRatingTests: XCTestCase {
    private let query = CriticRatingQuery(name: "Fixture", platform: .mac, steamAppID: 42)

    private func snak(_ value: Any) -> [String: Any] { ["datavalue": ["value": value]] }
    private func item(_ id: String) -> [String: Any] { snak(["id": id]) }
    private func claim(_ value: Any) -> [String: Any] { ["mainsnak": snak(value)] }
    private func score(_ value: String = "78/100", issuer: String = "Q21039459",
                       method: String = "Q114712322", platform: String? = nil,
                       referenced: Bool = true) -> [String: Any] {
        var quals: [String: Any] = ["P447": [item(issuer)], "P459": [item(method)]]
        if let platform { quals["P400"] = [item(platform)] }
        var value = claim(value)
        value["id"] = "Q10$statement"
        value["qualifiers"] = quals
        if referenced { value["references"] = [["snaks": ["P248": [item(issuer)]]]] }
        return value
    }
    private func payload(_ scores: [[String: Any]], steam: String = "42", second: Bool = false) throws -> Data {
        let entity: [String: Any] = ["claims": ["P31": [claim(["id": "Q7889"])],
                                               "P1733": [claim(steam)], "P444": scores]]
        var entities = ["Q10": entity]
        if second { entities["Q11"] = entity }
        return try JSONSerialization.data(withJSONObject: ["entities": entities])
    }
    func testReferencedAverageAndProportionalStars() throws {
        let rating = try XCTUnwrap(WikidataRatings.rating(in: payload([score()]), ids: ["Q10"], query: query))
        XCTAssertEqual(rating.score, 78)
        XCTAssertEqual(rating.source, .openCritic)
        XCTAssertEqual(rating.starFills.count, 5)
        XCTAssertEqual(rating.starFills.reduce(0, +), 3.9, accuracy: 0.0001)
        XCTAssertEqual(rating.starFills[3], 0.9, accuracy: 0.0001)
        XCTAssertEqual(rating.starFills[4], 0)
        XCTAssertEqual(rating.statementID, "Q10$statement")
        XCTAssertEqual(rating.sourceURL.absoluteString, "https://www.wikidata.org/wiki/Q10#Q10$statement")
    }
    func testRecommendationIndividualReviewsAndUnreferencedValuesAreNotCriticAverages() throws {
        for entry in [score("78%"), score(method: "Q119576498"), score(issuer: "Q207708"),
                      score(referenced: false), score("101/100"), score("-1/100"), score("4/5")] {
            XCTAssertNil(try WikidataRatings.rating(in: payload([entry]), ids: ["Q10"], query: query))
        }
        var multiple = score()
        multiple["qualifiers"] = ["P447": [item("Q21039459"), item("Q150248")]]
        XCTAssertNil(try WikidataRatings.rating(in: payload([multiple]), ids: ["Q10"], query: query))
        var unknownPlatform = score()
        unknownPlatform["qualifiers"] = ["P447": [item("Q21039459")], "P459": [item("Q114712322")],
                                          "P400": [["snaktype": "somevalue"]]]
        XCTAssertNil(try WikidataRatings.rating(in: payload([unknownPlatform]), ids: ["Q10"], query: query))
    }
    func testPlatformSpecificScoreWinsAndForeignPlatformsAreNeverBorrowed() throws {
        let mac = score("81/100", issuer: "Q150248", method: "Q106515043", platform: "Q14116")
        let windows = score("92/100", issuer: "Q150248", method: "Q106515043", platform: "Q1406")
        XCTAssertEqual(try WikidataRatings.rating(in: payload([score(), mac, windows]), ids: ["Q10"], query: query)?.score, 81)
        XCTAssertNil(try WikidataRatings.rating(in: payload([windows]), ids: ["Q10"], query: query))
        XCTAssertEqual(try WikidataRatings.rating(in: payload([score(), windows]), ids: ["Q10"], query: query)?.score, 78)
    }
    func testConflictingIdentityAmbiguityAndMalformedResponsesDoNotBecomeRatings() throws {
        XCTAssertNil(try WikidataRatings.rating(in: payload([score()], steam: "99"), ids: ["Q10"], query: query))
        XCTAssertNil(try WikidataRatings.rating(in: payload([score()], second: true), ids: ["Q10", "Q11"], query: query))
        XCTAssertThrowsError(try WikidataRatings.rating(in: Data("{\"error\":{\"code\":\"maxlag\"}}".utf8), ids: ["Q10"], query: query))
    }
    func testSearchRequiresExactTitleOrAliasNeverAnEditionOrSequel() throws {
        let data = Data("""
        {"search":[{"id":"Q10","label":"Fixture"},{"id":"Q11","label":"Fixture II"},
        {"id":"Q12","label":"Fixture Deluxe Edition"},{"id":"Q13","label":"Other","aliases":["Fixture"]}]}
        """.utf8)
        XCTAssertEqual(try WikidataRatings.ids(in: data, name: "Fixture"), ["Q10", "Q13"])
        XCTAssertThrowsError(try WikidataRatings.ids(in: Data("{}".utf8), name: "Fixture"))
    }
    func testCacheAndOfflineFallbackKeepTheOriginalValue() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let body = try payload([score()])
        let service = CriticRatingService(directory: dir, transport: { url in
            url.query?.contains("wbsearchentities") == true ? Data("{\"search\":[{\"id\":\"Q10\",\"label\":\"Fixture\"}]}".utf8) : body
        })
        let first = await service.load(query)
        XCTAssertEqual(first.rating?.score, 78)
        let offline = CriticRatingService(directory: dir, transport: { _ in throw URLError(.notConnectedToInternet) })
        let cached = await offline.load(query)
        XCTAssertEqual(cached.rating, first.rating)
        let stale = await offline.load(query, now: Date().addingTimeInterval(8 * 86400))
        XCTAssertEqual(stale.rating, first.rating)
        XCTAssertTrue(stale.isStale)
        let other = await offline.load(CriticRatingQuery(name: "Different", platform: .mac, steamAppID: 7))
        XCTAssertNil(other.rating)
    }
    func testMissingAnswersAreCachedAndConcurrentReadersShareRequests() async throws {
        actor Calls { var value = 0; func bump() { value += 1 } }
        let calls = Calls(), dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = CriticRatingService(directory: dir, transport: { _ in
            await calls.bump(); try await Task.sleep(nanoseconds: 20_000_000)
            return Data("{\"search\":[]}".utf8)
        })
        async let a = service.load(query)
        async let b = service.load(query)
        let results = await (a, b)
        XCTAssertNil(results.0.rating); XCTAssertNil(results.1.rating)
        _ = await service.load(query)
        let count = await calls.value
        XCTAssertEqual(count, 1)
    }

    func testCancellingLookupStopsTransportWithoutCachingAbsence() async throws {
        let started = expectation(description: "network request started")
        let stopped = expectation(description: "network request cancelled")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = CriticRatingService(directory: dir, transport: { _ in
            started.fulfill()
            do { try await Task.sleep(nanoseconds: 10_000_000_000); return Data() }
            catch { stopped.fulfill(); throw error }
        })
        let task = Task { await service.load(query) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        let answer = await task.value
        XCTAssertNil(answer.rating)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testAPIErrorBacksOffRatherThanPersistingAMissingScore() async throws {
        actor Calls { var count = 0; func bump() { count += 1 } }
        let calls = Calls(), dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = CriticRatingService(directory: dir, transport: { _ in
            await calls.bump(); return Data("{\"error\":{\"code\":\"maxlag\"}}".utf8)
        })
        _ = await service.load(query)
        _ = await service.load(query)
        let count = await calls.count
        XCTAssertEqual(count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testZeroIsARealScoreAndFormattingUsesTheRequestedRegion() throws {
        let zero = try XCTUnwrap(WikidataRatings.rating(in: payload([score("0/100")]), ids: ["Q10"], query: query))
        XCTAssertEqual(zero.starFills, [0, 0, 0, 0, 0])
        let decimal = try XCTUnwrap(WikidataRatings.rating(in: payload([score("78.5/100")]), ids: ["Q10"], query: query))
        XCTAssertEqual(decimal.number(locale: Locale(identifier: "it_IT")), "78,5/100")
    }

    func testDifferentGamesRequestThePublicAPIInSeries() async throws {
        actor Activity {
            var active = 0, maximum = 0
            func start() { active += 1; maximum = max(maximum, active) }
            func stop() { active -= 1 }
        }
        let activity = Activity(), dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = CriticRatingService(directory: dir, transport: { _ in
            await activity.start()
            try await Task.sleep(nanoseconds: 20_000_000)
            await activity.stop()
            return Data("{\"search\":[]}".utf8)
        })
        async let a = service.load(query)
        async let b = service.load(CriticRatingQuery(name: "Other", platform: .switch))
        _ = await (a, b)
        let maximum = await activity.maximum
        XCTAssertEqual(maximum, 1)
    }
}
