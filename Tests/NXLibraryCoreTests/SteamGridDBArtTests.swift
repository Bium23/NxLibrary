import XCTest
@testable import NXLibraryCore

final class SteamGridDBArtTests: XCTestCase {
    private final class Client: ArtworkHTTPClient, @unchecked Sendable {
        var routes: [String: (Int, Data)] = [:]
        var requests: [URLRequest] = []
        private let lock = NSLock()
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            lock.lock(); requests.append(request); lock.unlock()
            let key = request.url!.absoluteString
            let (status, body) = routes[key] ?? (404, Data())
            return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private let key = "0123456789abcdef0123456789abcdef"
    private let base = "https://www.steamgriddb.com/api/v2/"
    private let filters = "types=static&nsfw=false&humor=false&epilepsy=false&limit=12"

    private let search = Data("""
    {"success":true,"data":[
     {"id":35160,"name":"Donkey Kong","types":["eshop"],"verified":true},
     {"id":5483961,"name":"Donkey Kong: Bananza","types":[],"verified":true}]}
    """.utf8)

    private func listing(_ urls: [String], author: String? = "Goof14") -> Data {
        let items = urls.map { url in
            "{\"id\":1,\"url\":\"\(url)\",\"thumb\":\"\(url).thumb\",\"width\":600,\"height\":900"
                + (author.map { ",\"author\":{\"name\":\"\($0)\"}" } ?? "") + "}"
        }
        return Data("{\"success\":true,\"data\":[\(items.joined(separator: ","))]}".utf8)
    }

    // MARK: - Key

    func testKeyIsLettersAndDigitsOnly() {
        XCTAssertEqual(SteamGridDBKey.normalized("  \(key)\n"), key)
        XCTAssertNil(SteamGridDBKey.normalized("short"))
        XCTAssertNil(SteamGridDBKey.normalized("0123456789abcdef 0123456789abcdef"))
        XCTAssertNil(SteamGridDBKey.normalized("Bearer 0123456789abcdef0123"))
    }

    func testKeyIsKeptPrivately() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sgdb-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SteamGridDBKey(url: dir.appendingPathComponent("key"))
        XCTAssertNil(store.load())
        try store.save(key)
        XCTAssertEqual(store.load(), key)
        let mode = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        XCTAssertThrowsError(try store.save("not a key")) { XCTAssertEqual($0 as? SteamGridDBError, .invalidKey) }
        XCTAssertEqual(store.load(), key, "a refused key leaves the saved one")
        try store.remove()
        XCTAssertNil(store.load())
        XCTAssertNoThrow(try store.remove())
    }

    // MARK: - API

    func testTheGameIsTheOneWithTheGamesName() {
        XCTAssertEqual(SteamGridDBArt.gameID(in: search, matching: ["Donkey Kong Bananza"]), 5483961)
        XCTAssertNil(SteamGridDBArt.gameID(in: search, matching: ["Donkey Kong Country"]))
        XCTAssertNil(SteamGridDBArt.gameID(in: Data("nope".utf8), matching: ["Donkey Kong"]))
    }

    func testListingCreditsItsAuthorsWithPreviewAndFullFile() {
        let list = SteamGridDBArt.candidates(in: listing(["https://cdn2.steamgriddb.com/grid/a.png", "http://insecure/b.png"]), slot: .cover)
        XCTAssertEqual(list.map(\.url.absoluteString), ["https://cdn2.steamgriddb.com/grid/a.png.thumb"])
        XCTAssertEqual(list.first?.full?.absoluteString, "https://cdn2.steamgriddb.com/grid/a.png")
        XCTAssertEqual(list.first?.width, 600)
        XCTAssertEqual(list.first?.height, 900)
        XCTAssertEqual(list.first?.source, "SteamGridDB · Goof14")
        XCTAssertEqual(SteamGridDBArt.candidates(in: listing(["https://cdn2.steamgriddb.com/x.png"], author: nil), slot: .logo).first?.source,
                       "SteamGridDB")
    }

    func testFindAsksWithTheKeyForStillSafeArtOfEverySlot() async {
        let client = Client()
        client.routes[base + "search/autocomplete/Donkey%20Kong%20Bananza"] = (200, search)
        client.routes[base + "grids/game/5483961?dimensions=600x900,660x930&\(filters)"] = (200, listing(["https://cdn2.steamgriddb.com/grid/cover.png"]))
        client.routes[base + "heroes/game/5483961?\(filters)"] = (200, listing(["https://cdn2.steamgriddb.com/hero/h.png"]))
        client.routes[base + "logos/game/5483961?\(filters)"] = (200, listing(["https://cdn2.steamgriddb.com/logo/l.png"]))
        client.routes[base + "icons/game/5483961?\(filters)"] = (200, listing(["https://cdn2.steamgriddb.com/icon/i.png"]))
        client.routes[base + "grids/game/5483961?dimensions=512x512,1024x1024&\(filters)"] = (200, listing(["https://cdn2.steamgriddb.com/grid/sq.png"]))

        let game = await SteamGridDBArt.game(names: ["Donkey Kong Bananza"], key: key, client: client)
        let found = game?.candidates ?? []
        XCTAssertEqual(game?.page.absoluteString, "https://www.steamgriddb.com/game/5483961")
        XCTAssertEqual(found.filter { $0.slot == .cover }.compactMap(\.full?.lastPathComponent), ["cover.png"])
        XCTAssertEqual(found.filter { $0.slot == .background }.compactMap(\.full?.lastPathComponent), ["h.png"])
        XCTAssertEqual(found.filter { $0.slot == .logo }.compactMap(\.full?.lastPathComponent), ["l.png"])
        XCTAssertEqual(found.filter { $0.slot == .icon }.compactMap(\.full?.lastPathComponent), ["i.png", "sq.png"])
        XCTAssertTrue(client.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)" })
        XCTAssertTrue(client.requests.allSatisfy { $0.url?.host == "www.steamgriddb.com" }, "the key goes to SteamGridDB's API only")
    }

    func testFindForOneSlotAsksOnlyForIt() async {
        let client = Client()
        client.routes[base + "search/autocomplete/Donkey%20Kong%20Bananza"] = (200, search)
        client.routes[base + "logos/game/5483961?\(filters)"] = (200, listing(["https://cdn2.steamgriddb.com/logo/l.png"]))
        let found = await SteamGridDBArt.game(names: ["Donkey Kong Bananza"], key: key, slot: .logo, client: client)
        XCTAssertEqual(found?.candidates.map(\.slot), [.logo])
        XCTAssertEqual(client.requests.count, 2)
    }

    func testNoMatchingGameFindsNothingUnlessTyped() async {
        let client = Client()
        client.routes[base + "search/autocomplete/Some%20Other%20Game"] = (200, search)
        let found = await SteamGridDBArt.game(names: ["Some Other Game"], key: key, client: client)
        XCTAssertNil(found)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(SteamGridDBArt.gameID(in: search, matching: ["Some Other Game"], loose: true), 35160,
                       "a typed name takes SteamGridDB's first result")
    }

    func testKeyCheck() async {
        let client = Client()
        let url = base + "search/autocomplete/zelda"
        client.routes[url] = (200, Data("{\"success\":true,\"data\":[]}".utf8))
        if case .failure = await SteamGridDBArt.check(key: key, client: client) { XCTFail("an accepted key") }
        client.routes[url] = (401, Data())
        if case .failure(let error) = await SteamGridDBArt.check(key: key, client: client) { XCTAssertEqual(error, .rejected) }
        else { XCTFail("a refused key") }
        client.routes[url] = (503, Data())
        if case .failure(let error) = await SteamGridDBArt.check(key: key, client: client) { XCTAssertEqual(error, .unreachable) }
        else { XCTFail("a server error") }
    }

    func testOnlineArtworkNeverAsksSteamGridDBOrLaunchBox() async {
        let client = Client()
        _ = await OnlineArtwork.find(names: ["Donkey Kong Bananza"], client: client)
        XCTAssertFalse(client.requests.contains { $0.url?.host == "www.steamgriddb.com" }, "browsed on its own")
        XCTAssertFalse(client.requests.contains { $0.url?.host == "gamesdb.launchbox-app.com" }, "browsed on its own")
    }

    // MARK: - Browse

    func testBrowseSearchesTheGamesNamesUntilTheFieldChanges() {
        let names = ["Donkey Kong Bananza", "DK Bananza"]
        XCTAssertEqual(ArtworkBrowseSource.names(for: " donkey kong bananza ", gameNames: names), names)
        XCTAssertEqual(ArtworkBrowseSource.names(for: "Bananza", gameNames: names), ["Bananza"])
        XCTAssertEqual(ArtworkBrowseSource.names(for: "  ", gameNames: names), [])
    }

    func testBrowseSteamGridDBNeedsTheKey() async {
        let client = Client()
        let none = await ArtworkBrowseSource.steamGridDB.search("Donkey Kong Bananza", gameNames: ["Donkey Kong Bananza"],
                                                                switch2: true, key: nil, client: client)
        XCTAssertNil(none.page)
        XCTAssertTrue(client.requests.isEmpty, "nothing is asked without a key")
        client.routes[base + "search/autocomplete/Donkey%20Kong%20Bananza"] = (200, search)
        client.routes[base + "logos/game/5483961?\(filters)"] = (200, listing(["https://cdn2.steamgriddb.com/logo/l.png"]))
        let found = await ArtworkBrowseSource.steamGridDB.search("Donkey Kong Bananza", gameNames: ["Donkey Kong Bananza"],
                                                                 switch2: true, key: key, client: client)
        XCTAssertEqual(found.page?.absoluteString, "https://www.steamgriddb.com/game/5483961")
        XCTAssertEqual(found.candidates.map(\.source), ["SteamGridDB · Goof14"])
    }

    func testBrowseLaunchBoxListsTheGamesImages() async {
        let client = LaunchBoxArtTests.Client()
        client.routes[LaunchBoxArtTests.search] = LaunchBoxArtTests.card("424483-donkey-kong-bananza", "Donkey Kong Bananza", "Nintendo Switch 2")
        client.routes[LaunchBoxArtTests.details] = LaunchBoxArtTests.gamePage
        let found = await ArtworkBrowseSource.launchBox.search("Donkey Kong Bananza", gameNames: ["Donkey Kong Bananza"],
                                                               switch2: true, key: nil, client: client)
        XCTAssertEqual(found.page?.absoluteString, LaunchBoxArtTests.details)
        XCTAssertEqual(found.candidates.filter { $0.slot == .cover }.count, 2)
    }
}
