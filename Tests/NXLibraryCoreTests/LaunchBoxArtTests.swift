import XCTest
@testable import NXLibraryCore

final class LaunchBoxArtTests: XCTestCase {
    final class Client: ArtworkHTTPClient, @unchecked Sendable {
        var routes: [String: String] = [:]
        var asked: [String] = []
        private let lock = NSLock()
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let url = request.url!.absoluteString
            lock.lock(); asked.append(url); let body = routes[url]; lock.unlock()
            return (Data((body ?? "").utf8), HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200,
                                                              httpVersion: nil, headerFields: nil)!)
        }
    }

    /// Cards as the search page writes them (trimmed).
    static func card(_ slug: String, _ title: String, _ platform: String) -> String {
        """
        <div class="col-md-6"> <a class="list-item link-no-underline" href="/games/details/\(slug)"> <div class="gameCard">
        <img src="https://images.launchbox-app.com/x.jpg" alt="\(title)" /> <div class="cardContent"> <div class="cardTitle">
        <h3 b-x>\(title)</h3> <p b-x>\(platform)</p> </div></div></div></a></div>
        """
    }

    typealias Image = (kind: String, region: String?, preview: String, full: String, width: Int, height: Int)

    /// A game page whose Nuxt payload lists `images` the way LaunchBox writes it: one flat array, objects whose
    /// values are indices of other entries.
    static func page(_ images: [Image]) -> String {
        var array: [Any] = [["data": 1], ["gameImages": 2], []]
        var list: [Int] = []
        for image in images {
            let at = array.count
            list.append(at)
            array.append([String: Int]())
            func add(_ value: Any) -> Int { array.append(value); return array.count - 1 }
            var object: [String: Int] = [:]
            object["imageFileName"] = add(image.preview)
            object["imageTypeName"] = add(image.kind)
            object["width"] = add(400)
            if let region = image.region { object["regionName"] = add(region) }
            object["fullGameImageFileName"] = add(image.full)
            object["fullGameImageWidth"] = add(image.width)
            object["fullGameImageHeight"] = add(image.height)
            array[at] = object
        }
        array[2] = list
        let json = String(data: try! JSONSerialization.data(withJSONObject: array), encoding: .utf8)!
        return "<html><body><img src=\"https://images.launchbox-app.com//thumb.jpg\" alt=\"x\">"
            + "<script type=\"application/json\" data-nuxt-data=\"nuxt-app\" data-ssr=\"true\" id=\"__NUXT_DATA__\">\(json)</script></body></html>"
    }

    static var gamePage: String {
        let fixed: [Image] = [("Box - Back", "North America", "r2_back.jpg", "r2_back-full.jpg", 1157, 1883),
                              ("Box - Front", "Europe", "front-eu.jpg", "front-eu-full.jpg", 1164, 1902),
                              ("Box - Front - Reconstructed", "North America", "r2_recon.png", "r2_recon-full.png", 1446, 2342),
                              ("Box - Spine", "North America", "r2_spine.jpg", "r2_spine-full.jpg", 117, 1883),
                              ("Clear Logo", "World", "logo.png", "logo-full.png", 1500, 570)]
        let shots: [Image] = (1...8).map { ("Screenshot - Gameplay", "World", "shot\($0).png", "shot\($0)-full.png", 2880, 1620) }
        // As on LaunchBox, the fanart comes after the screenshots; the picker lists it first.
        return page(fixed + shots + [("Fanart - Background", "World", "fanart.jpg", "fanart-full.jpg", 1920, 1080), ("Square", "World", "r2_square.jpg", "r2_square-full.jpg", 950, 950)])
    }

    static let search = "https://gamesdb.launchbox-app.com/games/results/Donkey%20Kong%20Bananza"
    static let details = "https://gamesdb.launchbox-app.com/games/details/424483-donkey-kong-bananza"

    func testSearchURLKeepsTheNameInThePath() {
        XCTAssertEqual(LaunchBoxArt.searchURL(for: "Donkey Kong Bananza")?.absoluteString, Self.search)
        XCTAssertEqual(LaunchBoxArt.searchURL(for: "Fate/Samurai")?.absoluteString,
                       "https://gamesdb.launchbox-app.com/games/results/Fate%2FSamurai")
        XCTAssertNil(LaunchBoxArt.searchURL(for: "  "))
    }

    func testResultsAndTheSwitchEntryOfThisGame() {
        let html = Self.card("441036-donkey-kong-country-2-bonus-bananza", "Donkey Kong Country 2: Bonus Bananza", "Super Nintendo")
            + Self.card("10-donkey-kong-bananza", "Donkey Kong Bananza", "Nintendo Switch")
            + Self.card("424483-donkey-kong-bananza", "Donkey Kong Bananza", "Nintendo Switch 2")
        let results = LaunchBoxArt.results(in: html)
        XCTAssertEqual(results.map(\.platform), ["Super Nintendo", "Nintendo Switch", "Nintendo Switch 2"])
        XCTAssertEqual(LaunchBoxArt.pick(results, names: ["Donkey Kong Bananza"], switch2: true)?.path, "/games/details/424483-donkey-kong-bananza")
        XCTAssertEqual(LaunchBoxArt.pick(results, names: ["Donkey Kong Bananza"], switch2: false)?.path, "/games/details/10-donkey-kong-bananza")
        XCTAssertNil(LaunchBoxArt.pick(results, names: ["Donkey Kong"], switch2: false), "another game is never taken")
        let snes = LaunchBoxArt.results(in: Self.card("1-x", "Donkey Kong Bananza", "Super Nintendo"))
        XCTAssertNil(LaunchBoxArt.pick(snes, names: ["Donkey Kong Bananza"], switch2: false), "only a Switch entry")
        XCTAssertNil(LaunchBoxArt.pick(snes, names: ["Donkey Kong Bananza"], switch2: false, loose: true), "even typed")
    }

    func testAMacGameTakesItsComputerEntryNeverAConsoleOne() {
        let results = LaunchBoxArt.results(in: Self.card("3-ps", "The Witcher 3: Wild Hunt", "Sony Playstation 4")
                                           + Self.card("2-sw", "The Witcher 3: Wild Hunt", "Nintendo Switch")
                                           + Self.card("1-win", "The Witcher 3: Wild Hunt", "Windows"))
        XCTAssertEqual(LaunchBoxArt.pick(results, names: ["The Witcher 3: Wild Hunt"], computer: true)?.path, "/games/details/1-win")
        let both = LaunchBoxArt.results(in: Self.card("1-win", "Fixture", "Windows") + Self.card("4-mac", "Fixture", "Apple Mac OS"))
        XCTAssertEqual(LaunchBoxArt.pick(both, names: ["Fixture"], computer: true)?.path, "/games/details/4-mac", "the Mac entry first")
        let consoles = LaunchBoxArt.results(in: Self.card("2-sw", "Fixture", "Nintendo Switch"))
        XCTAssertNil(LaunchBoxArt.pick(consoles, names: ["Fixture"], computer: true, loose: true))
        XCTAssertEqual(LaunchBoxArt.pick(results, names: ["The Witcher 3: Wild Hunt"], switch2: false)?.path, "/games/details/2-sw",
                       "a Switch game still takes the Switch entry")
    }

    func testATypedNameTakesTheFirstSwitchResult() {
        let results = LaunchBoxArt.results(in: Self.card("2-y", "Mario Kart 64", "Nintendo 64")
                                           + Self.card("1-x", "Super Mario Odyssey", "Nintendo Switch"))
        XCTAssertNil(LaunchBoxArt.pick(results, names: ["mario odyssey"], switch2: false))
        XCTAssertEqual(LaunchBoxArt.pick(results, names: ["mario odyssey"], switch2: false, loose: true)?.path, "/games/details/1-x")
    }

    func testPageImagesGoToTheirSlotsWithKindRegionAndFullFile() {
        let list = LaunchBoxArt.candidates(in: Self.gamePage)
        let covers = list.filter { $0.slot == .cover }
        XCTAssertEqual(covers.map(\.source),
                       ["LaunchBox · Box - Front (Europe)", "LaunchBox · Box - Front - Reconstructed (North America)"])
        XCTAssertEqual(covers.first?.url.absoluteString, "https://images.launchbox-app.com/front-eu.jpg", "the grid loads the preview")
        XCTAssertEqual(covers.first?.full?.absoluteString, "https://images.launchbox-app.com/front-eu-full.jpg", "a choice the full file")
        XCTAssertEqual(covers.first?.width, 1164)
        XCTAssertEqual(covers.first?.height, 1902)
        XCTAssertEqual(list.filter { $0.slot == .logo }.map(\.source), ["LaunchBox · Clear Logo (World)"])
        XCTAssertEqual(list.filter { $0.slot == .icon }.map(\.source), ["LaunchBox · Square (World)"])
        let backgrounds = list.filter { $0.slot == .background }
        XCTAssertEqual(backgrounds.first?.source, "LaunchBox · Fanart - Background (World)")
        XCTAssertEqual(backgrounds.count, 1 + 8, "browsing lists every screenshot")
        XCTAssertFalse(list.contains { $0.url.absoluteString.contains("back") || $0.url.absoluteString.contains("spine") })
    }

    func testPayloadNamesThatAreNotPlainFilesAreSkipped() {
        let html = Self.page([("Clear Logo", nil, "../evil.png", "logo-full.png", 1, 1),
                              ("Clear Logo", nil, "logo.png", "https://elsewhere.example/x.png", 1, 1),
                              ("Clear Logo", nil, "ok.png", "ok-full.png", 10, 10)])
        let list = LaunchBoxArt.candidates(in: html)
        XCTAssertEqual(list.map(\.full?.absoluteString), ["https://images.launchbox-app.com/ok-full.png"])
        XCTAssertEqual(list.first?.source, "LaunchBox · Clear Logo", "no region, no brackets")
        XCTAssertTrue(LaunchBoxArt.candidates(in: "<html>no payload</html>").isEmpty)
    }

    func testGameSearchesThenReadsTheGamesPage() async {
        let client = Client()
        client.routes[Self.search] = Self.card("424483-donkey-kong-bananza", "Donkey Kong Bananza", "Nintendo Switch 2")
        client.routes[Self.details] = Self.gamePage
        let game = await LaunchBoxArt.game(names: ["Donkey Kong Bananza"], switch2: true, client: client)
        XCTAssertEqual(game?.page.absoluteString, Self.details)
        XCTAssertEqual(game?.candidates.filter { $0.slot == .logo }.count, 1)
        XCTAssertEqual(client.asked.count, 2)
    }

    func testScreenshotsAreTheGameplayOnesAtFullSize() async {
        let client = Client()
        client.routes[Self.search] = Self.card("424483-donkey-kong-bananza", "Donkey Kong Bananza", "Nintendo Switch 2")
        client.routes[Self.details] = Self.gamePage
        let shots = await LaunchBoxArt.screenshots(names: ["Donkey Kong Bananza"], switch2: true, client: client)
        XCTAssertEqual(shots?.count, LaunchBoxArt.screenshotLimit)
        XCTAssertEqual(shots?.first?.lastPathComponent, "shot1-full.png")
        let none = Client()
        none.routes[Self.search] = "<html></html>"
        let missing = await LaunchBoxArt.screenshots(names: ["Donkey Kong Bananza"], switch2: true, client: none)
        XCTAssertNil(missing, "no game found: nothing to keep")
    }

    func testAPageThatChangedFindsNothing() async {
        let client = Client()
        client.routes[Self.search] = "<html>new layout</html>"
        let game = await LaunchBoxArt.game(names: ["Donkey Kong Bananza"], switch2: true, client: client)
        XCTAssertNil(game)
    }
}
