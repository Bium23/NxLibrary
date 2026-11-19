import XCTest
@testable import NXLibraryCore

final class WikipediaDescriptionTests: XCTestCase {
    private let english = "Stardew Valley is a farming simulation game where you inherit your grandfather's old farm plot."
    private let italian = "Stardew Valley è un videogioco indipendente del 2016, sviluppato da ConcernedApe e pubblicato da Chucklefish."
    private let simplified = "《超级马力欧兄弟 惊奇》是一款由任天堂企划制作本部开发，并由任天堂发行在任天堂Switch平台上的平台动作游戏，于2023年10月20日发售。"
    private let traditional = "《超級瑪利歐兄弟 驚奇》是一款由任天堂企劃製作本部開發，並由任天堂發行在任天堂Switch平台上的平台動作遊戲，於2023年10月20日發售。"

    // MARK: When to look

    func testEnglishStoreTextIsReplacedForAnItalianReader() {
        XCTAssertTrue(WikipediaDescriptions.wanted(description: english, descriptionLanguage: "en", language: .italian))
    }

    func testStoreTextInTheAppLanguageIsKept() {
        XCTAssertFalse(WikipediaDescriptions.wanted(description: italian, descriptionLanguage: "it", language: .italian))
        XCTAssertFalse(WikipediaDescriptions.wanted(description: english, descriptionLanguage: "en", language: .english))
    }

    /// Steam does not say which language it answered in; the text itself does.
    func testSteamEnglishFallbackIsReadFromTheText() {
        XCTAssertTrue(WikipediaDescriptions.wanted(description: english, descriptionLanguage: nil, language: .italian))
        XCTAssertFalse(WikipediaDescriptions.wanted(description: italian, descriptionLanguage: nil, language: .italian))
    }

    func testThePlayersOwnChoiceIsNeverReplaced() {
        XCTAssertFalse(WikipediaDescriptions.wanted(description: english, descriptionLanguage: "custom", language: .italian))
        XCTAssertFalse(WikipediaDescriptions.wanted(description: "", descriptionLanguage: "custom", language: .italian))
    }

    func testAMissingDescriptionIsLookedForInAnyLanguage() {
        XCTAssertTrue(WikipediaDescriptions.wanted(description: "  ", descriptionLanguage: "en", language: .english))
    }

    func testTraditionalChineseIsNotSimplified() {
        XCTAssertFalse(WikipediaDescriptions.wanted(description: simplified, descriptionLanguage: nil, language: .chineseSimplified))
        XCTAssertTrue(WikipediaDescriptions.wanted(description: traditional, descriptionLanguage: nil, language: .chineseSimplified))
    }

    func testShortTextIsKept() {
        XCTAssertFalse(WikipediaDescriptions.wanted(description: "A farming game.", descriptionLanguage: nil, language: .italian))
    }

    func testEditions() {
        XCTAssertEqual(WikipediaDescriptions.edition(for: .chineseSimplified)?.code, "zh")
        XCTAssertEqual(WikipediaDescriptions.edition(for: .chineseSimplified)?.variant, "zh-cn")
        XCTAssertEqual(WikipediaDescriptions.edition(for: .portugueseBrazil)?.code, "pt")
        XCTAssertNil(WikipediaDescriptions.edition(for: .automatic))
    }

    // MARK: Parsing

    func testSitelinkComesFromTheMatchedVideoGame() throws {
        let data = try entities(steam: "413150", links: ["itwiki": "Stardew Valley", "zhwiki": "星露谷物语"])
        let query = CriticRatingQuery(name: "Stardew Valley", platform: .mac, steamAppID: 413150)
        XCTAssertEqual(try WikipediaDescriptions.sitelink(in: data, ids: ["Q10"], query: query, requireSteamID: true, edition: "it"),
                       "Stardew Valley")
        XCTAssertNil(try WikipediaDescriptions.sitelink(in: data, ids: ["Q10"], query: query, requireSteamID: true, edition: "de"))
    }

    func testAnotherSteamGameNeverLendsItsArticle() throws {
        let data = try entities(steam: "1", links: ["itwiki": "Other game"])
        let query = CriticRatingQuery(name: "Stardew Valley", platform: .mac, steamAppID: 413150)
        XCTAssertNil(try WikipediaDescriptions.sitelink(in: data, ids: ["Q10"], query: query, requireSteamID: true, edition: "it"))
    }

    func testIntroductionKeepsParagraphsAndItsPage() throws {
        let body = """
        {"query":{"pages":[{"title":"Stardew Valley","fullurl":"https://it.wikipedia.org/wiki/Stardew_Valley",
        "extract":"\(italian)\\nIl videogioco è ispirato alla serie Harvest Moon."}]}}
        """
        let result = try XCTUnwrap(WikipediaDescriptions.description(in: Data(body.utf8), edition: "it"))
        XCTAssertEqual(result.text, italian + "\n\nIl videogioco è ispirato alla serie Harvest Moon.")
        XCTAssertEqual(result.pageURL.absoluteString, "https://it.wikipedia.org/wiki/Stardew_Valley")
    }

    func testMissingPageOrForeignLinkGivesNothing() throws {
        let missing = #"{"query":{"pages":[{"title":"X","missing":true}]}}"#
        XCTAssertNil(try WikipediaDescriptions.description(in: Data(missing.utf8), edition: "it"))
        let foreign = #"{"query":{"pages":[{"title":"X","fullurl":"https://example.com/x","extract":"\#(italian)"}]}}"#
        XCTAssertNil(try WikipediaDescriptions.description(in: Data(foreign.utf8), edition: "it"))
    }

    func testIntroURLAsksForPlainTextAndTheSimplifiedVariant() throws {
        let url = try XCTUnwrap(WikipediaDescriptions.introURL(edition: "zh", title: "超級瑪利歐兄弟 驚奇", variant: "zh-cn"))
        XCTAssertEqual(url.host, "zh.wikipedia.org")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(.init(name: "variant", value: "zh-cn")))
        XCTAssertTrue(items.contains(.init(name: "explaintext", value: "1")))
        XCTAssertNil(WikipediaDescriptions.introURL(edition: "evil.example", title: "X", variant: nil))
    }

    func testDownloadRefusesHostsOutsideWikimedia() async {
        do {
            _ = try await WikipediaDescriptionService.download(URL(string: "https://example.com/w/api.php")!)
            XCTFail("an unknown host was accepted")
        } catch {}
    }

    // MARK: Service

    func testSteamGameGetsItsArticleAndTheAnswerIsCached() async throws {
        let dir = temporaryDirectory()
        let calls = Counter()
        let entity = try entities(steam: "413150", links: ["itwiki": "Stardew Valley"])
        let intro = Data("""
        {"query":{"pages":[{"title":"Stardew Valley","fullurl":"https://it.wikipedia.org/wiki/Stardew_Valley","extract":"\(italian)"}]}}
        """.utf8)
        let service = WikipediaDescriptionService(directory: dir, transport: { url in
            await calls.add()
            if url.host == "it.wikipedia.org" { return intro }
            if url.query?.contains("wbgetentities") == true { return entity }
            return Data(#"{"query":{"search":[{"title":"Q10","ns":0}]}}"#.utf8)
        })
        let query = CriticRatingQuery(name: "Stardew Valley", platform: .mac, steamAppID: 413150)
        let first = await service.load(query, language: .italian)
        XCTAssertEqual(first?.text, italian)
        let made = await calls.value
        let again = await service.load(query, language: .italian)
        XCTAssertEqual(again, first)
        let after = await calls.value
        XCTAssertEqual(after, made, "the second load reads the cache")
    }

    /// Clear in Storage → Metadata cache also forgets Wikipedia's texts, so a wrong or old article is asked again.
    func testCacheIsMeasuredAndCleared() async throws {
        let dir = temporaryDirectory()
        let entity = try entities(steam: "413150", links: ["itwiki": "Stardew Valley"])
        let intro = Data("""
        {"query":{"pages":[{"title":"Stardew Valley","fullurl":"https://it.wikipedia.org/wiki/Stardew_Valley","extract":"\(italian)"}]}}
        """.utf8)
        let service = WikipediaDescriptionService(directory: dir, transport: { url in
            if url.host == "it.wikipedia.org" { return intro }
            if url.query?.contains("wbgetentities") == true { return entity }
            return Data(#"{"query":{"search":[{"title":"Q10","ns":0}]}}"#.utf8)
        })
        _ = await service.load(CriticRatingQuery(name: "Stardew Valley", platform: .mac, steamAppID: 413150), language: .italian)
        XCTAssertGreaterThan(service.cacheSize(), 0)
        service.clearCache()
        XCTAssertEqual(service.cacheSize(), 0)
    }

    func testANetworkErrorIsNotSavedAsNoArticle() async throws {
        let dir = temporaryDirectory()
        let failing = WikipediaDescriptionService(directory: dir, transport: { _ in throw URLError(.notConnectedToInternet) })
        let query = CriticRatingQuery(name: "Stardew Valley", platform: .mac, steamAppID: 413150)
        let none = await failing.load(query, language: .italian)
        XCTAssertNil(none)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertTrue(files.isEmpty)
    }

    // MARK: Fixtures

    private func entities(steam: String, links: [String: String]) throws -> Data {
        let claim = { (value: Any) -> [String: Any] in ["mainsnak": ["datavalue": ["value": value]]] }
        let entity: [String: Any] = [
            "claims": ["P31": [claim(["id": "Q7889"])], "P1733": [claim(steam)]],
            "sitelinks": links.mapValues { ["title": $0] }
        ]
        return try JSONSerialization.data(withJSONObject: ["entities": ["Q10": entity]])
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private actor Counter {
    private(set) var value = 0
    func add() { value += 1 }
}
