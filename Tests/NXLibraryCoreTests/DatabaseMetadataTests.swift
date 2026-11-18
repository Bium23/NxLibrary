import XCTest
@testable import NXLibraryCore

final class DatabaseMetadataTests: XCTestCase {
    private let query = CriticRatingQuery(name: "Fixture™", platform: .switch2)
    private let page = URL(string: "https://gamesdb.launchbox-app.com/games/details/10-fixture")!

    private func launchBoxPage(platform: String = "Nintendo Switch 2", name: String = "Fixture", id: Int = 10) throws -> String {
        var graph: [Any] = []
        func add(_ value: Any) -> Int { graph.append(value); return graph.count - 1 }
        let platformName = add(platform), platformObject = add(["name": platformName])
        let genre = add("Adventure"), genreObject = add(["name": genre]), genres = add([genreObject])
        let developer = add("Studio"), developerObject = add(["name": developer]), developers = add([developerObject])
        let title = add(name), key = add(id), overview = add("A <b>description</b>."), date = add("2026-11-05")
        _ = add(["gameKey": key, "name": title, "platform": platformObject, "overview": overview,
                 "gameGenres": genres, "gameDevelopers": developers, "gamePublishers": developers, "releaseDate": date])
        let json = String(decoding: try JSONSerialization.data(withJSONObject: graph), as: UTF8.self)
        return "<script id=\"__NUXT_DATA__\" type=\"application/json\">\(json)</script>"
    }
    private func card(_ id: Int, title: String = "Fixture", platform: String = "Nintendo Switch 2") -> String {
        "<a href=\"/games/details/\(id)-fixture\"><h3>\(title)</h3><p>\(platform)</p></a>"
    }

    func testLaunchBoxChecksTheFinalIdentityAndOffersFiveFields() throws {
        let result = try DatabaseMetadataParser.launchBox(in: launchBoxPage(), query: query, page: page)
        let preview = try XCTUnwrap(result.preview)
        XCTAssertEqual(preview.option(for: .description)?.value, "A description.")
        XCTAssertEqual(preview.option(for: .genres)?.value, "Adventure")
        XCTAssertEqual(preview.option(for: .developer)?.value, "Studio")
        XCTAssertEqual(preview.option(for: .publisher)?.value, "Studio")
        XCTAssertEqual(preview.option(for: .releaseDate)?.value, "2026-11-05")
        XCTAssertEqual(preview.option(for: .description)?.source, "LaunchBox · Nintendo Switch 2")
        XCTAssertEqual(try DatabaseMetadataParser.launchBox(in: launchBoxPage(id: 99), query: query, page: page).issue, .unavailable)
        XCTAssertEqual(try DatabaseMetadataParser.launchBox(in: launchBoxPage(name: "Fixture II"), query: query, page: page).issue, .notFound)
    }

    func testMatchingKeepsEditionsAndPrefersMacButLabelsPCWithoutBorrowingItsDate() throws {
        let mac = CriticRatingQuery(name: "Fixture", platform: .mac)
        let html = card(1, platform: "Windows") + card(2, platform: "Apple Mac OS") + card(3, title: "Fixture Deluxe Edition", platform: "Apple Mac OS")
        XCTAssertEqual(DatabaseMetadataParser.launchBoxCandidates(in: html, query: mac).map(\.url.lastPathComponent), ["2-fixture"])
        let result = try DatabaseMetadataParser.launchBox(in: launchBoxPage(platform: "Windows"), query: mac, page: page)
        XCTAssertEqual(result.preview?.option(for: .description)?.source, "LaunchBox · Windows")
        XCTAssertNil(result.preview?.option(for: .releaseDate))
        let foreign = try DatabaseMetadataParser.launchBox(in: launchBoxPage(platform: "Nintendo Switch"), query: query, page: page)
        XCTAssertEqual(foreign.issue, .notFound)
    }

    func testTheGamesDBChecksTitlePlatformAndDateInsteadOfAnyParagraph() throws {
        let html = """
        <h1>Fixture</h1><p>Platform: <a href="/platform.php?id=1">PC</a></p>
        <p>Developer(s): <a>Studio</a></p><p>Publishers(s): <a>Publisher</a></p>
        <p>ReleaseDate: 2026-11-05</p><p>Genre(s): Adventure | Puzzle</p>
        <p class="game-overview">A &amp; B <b>description</b>.</p>
        """
        let mac = CriticRatingQuery(name: "Fixture", platform: .mac)
        let url = URL(string: "https://thegamesdb.net/game.php?id=10")!
        let result = DatabaseMetadataParser.theGamesDB(in: html, query: mac, page: url)
        XCTAssertEqual(result.preview?.option(for: .description)?.value, "A & B description.")
        XCTAssertEqual(result.preview?.option(for: .developer)?.value, "Studio")
        XCTAssertEqual(result.preview?.option(for: .genres)?.value, "Adventure, Puzzle")
        XCTAssertNil(result.preview?.option(for: .releaseDate))
        XCTAssertEqual(DatabaseMetadataParser.theGamesDB(in: html, query: query, page: url).issue, .notFound)
    }

    func testOneFetchPerPageThenNoRequestsAcrossFieldsOrFreshReopenAndStaleWorksOffline() async throws {
        actor Calls { var urls: [URL] = []; func add(_ url: URL) { urls.append(url) } }
        let calls = Calls(), search = card(10), detail = try launchBoxPage()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = DatabaseMetadataService(database: .launchBox, directory: root, transport: { request in
            await calls.add(request.url!)
            let html = request.url!.path.contains("/results/") ? search : detail
            return (Data(html.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let first = await service.load(query)
        XCTAssertNotNil(first.preview)
        for field in MetadataField.allCases { _ = first.preview?.option(for: field) }
        let next = await service.load(query)
        XCTAssertEqual(next.preview, first.preview)
        let urls = await calls.urls
        XCTAssertEqual(urls.count, 2)
        let offline = DatabaseMetadataService(database: .launchBox, directory: root, transport: { _ in throw URLError(.notConnectedToInternet) })
        let stale = await offline.load(query, now: Date().addingTimeInterval(8 * 86400))
        XCTAssertEqual(stale.preview, first.preview)
        XCTAssertTrue(stale.isStale)
    }

    func testAmbiguousSearchNeverDownloadsAnArbitraryGamePage() async {
        let search = card(10) + card(11)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = DatabaseMetadataService(database: .launchBox, directory: root, transport: { request in
            XCTAssertTrue(request.url!.path.contains("/results/"))
            return (Data(search.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = await service.load(query)
        XCTAssertEqual(result.issue, .ambiguous)
        XCTAssertNil(result.preview)
    }

    func testConcurrentReadersShareTheLookup() async throws {
        actor Calls { var count = 0; func add() { count += 1 } }
        let calls = Calls(), search = card(10), detail = try launchBoxPage()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = DatabaseMetadataService(database: .launchBox, directory: root, transport: { request in
            await calls.add()
            try await Task.sleep(nanoseconds: 10_000_000)
            return (Data((request.url!.path.contains("/results/") ? search : detail).utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        async let first = service.load(query)
        async let second = service.load(query)
        let results = await (first, second)
        XCTAssertEqual(results.0.preview, results.1.preview)
        let count = await calls.count
        XCTAssertEqual(count, 2)
    }

    func testCancellationStopsTheRequestAndDoesNotCacheAnAbsence() async throws {
        let started = expectation(description: "request starts"), stopped = expectation(description: "request cancels")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = DatabaseMetadataService(database: .launchBox, directory: root, transport: { _ in
            started.fulfill()
            do { try await Task.sleep(nanoseconds: 10_000_000_000); throw URLError(.timedOut) }
            catch { stopped.fulfill(); throw error }
        })
        let query = query
        let task = Task { await service.load(query) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        let cancelled = await task.value
        XCTAssertEqual(cancelled.issue, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testOversizedOrRedirectedResponsesNeverBecomeMetadataOrNegativeCache() async {
        for redirected in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let service = DatabaseMetadataService(database: .launchBox, directory: root, transport: { request in
                let url = redirected ? URL(string: "https://other.example/unexpected")! : request.url!
                return (redirected ? Data() : Data(repeating: 65, count: 2_097_153),
                        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
            let result = await service.load(query)
            XCTAssertEqual(result.issue, .unavailable)
            XCTAssertNil(result.preview)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        }
    }

    func testFailedRefreshCanRetryWithoutANegativeCacheBlockingIt() async throws {
        actor Calls { var count = 0; func next() -> Int { count += 1; return count } }
        let calls = Calls(), search = card(10), detail = try launchBoxPage()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = DatabaseMetadataService(database: .launchBox, directory: root, transport: { request in
            let attempt = await calls.next()
            return (Data((request.url!.path.contains("/results/") ? search : detail).utf8),
                    HTTPURLResponse(url: request.url!, statusCode: attempt == 1 ? 503 : 200, httpVersion: nil, headerFields: nil)!)
        })
        let failed = await service.load(query)
        XCTAssertEqual(failed.issue, .unavailable)
        let retried = await service.load(query)
        XCTAssertNotNil(retried.preview)
    }
}
