import XCTest
@testable import NXLibraryCore

final class MoreArtworkSourcesTests: XCTestCase {
    private final class RoutedClient: ArtworkHTTPClient {
        var routes: [String: Data] = [:]
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let body = routes[request.url!.absoluteString]
            return (body ?? Data(), HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200,
                                                    httpVersion: nil, headerFields: nil)!)
        }
    }

    private func query(_ url: URL?) -> [String: String] {
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    private func by(_ list: [ArtworkCandidate], _ slot: ArtworkSlot) -> [String] {
        list.filter { $0.slot == slot }.map(\.url.absoluteString)
    }

    // MARK: - Names

    func testAStoreNameMatchesTheSameGameOrAnEditionOfIt() {
        XCTAssertTrue(ArtworkNames.matches("Hollow Knight", ["Hollow Knight™"]))
        XCTAssertTrue(ArtworkNames.matches("Hollow Knight: Voidheart Edition", ["Hollow Knight"]))
        XCTAssertTrue(ArtworkNames.matches("Celeste - Nintendo Switch Edition", ["Celeste"]))
        XCTAssertTrue(ArtworkNames.matches("Hades", ["Hades for Nintendo Switch"]))
        XCTAssertFalse(ArtworkNames.matches("Hollow Knight: Silksong", ["Hollow Knight"]))
        XCTAssertFalse(ArtworkNames.matches("LumenTale: Memories of Trey - Deluxe DLC", ["LumenTale: Memories of Trey"]))
        XCTAssertFalse(ArtworkNames.matches("Hollow Knight", ["Hollow"]))
        XCTAssertFalse(ArtworkNames.matches("", [""]))
    }

    // MARK: - Xbox Store

    private let xboxSuggest = Data("""
    {"Results":[
     {"ProductFamilyName":"Games","Products":[{"ProductId":"9N116V0599HB","Type":"Game","Title":"Hollow Knight: Silksong"}]},
     {"ProductFamilyName":"Games","Products":[{"ProductId":"9AAADLC","Type":"Durable","Title":"Hollow Knight"},
                                              {"ProductId":"9MW9469V91LM","Type":"Game","Title":"Hollow Knight: Voidheart Edition"}]}]}
    """.utf8)

    private let xboxProduct = Data("""
    {"Products":[{"LocalizedProperties":[{"ProductTitle":"Hollow Knight: Voidheart Edition","Images":[
     {"ImagePurpose":"Logo","Width":300,"Height":300,"Uri":"//store-images.s-microsoft.com/image/logo"},
     {"ImagePurpose":"Screenshot","Width":1920,"Height":1080,"Uri":"//store-images.s-microsoft.com/image/s1"},
     {"ImagePurpose":"Poster","Width":1440,"Height":2160,"Uri":"//store-images.s-microsoft.com/image/poster"},
     {"ImagePurpose":"BoxArt","Width":2160,"Height":2160,"Uri":"//store-images.s-microsoft.com/image/box"},
     {"ImagePurpose":"SuperHeroArt","Width":3840,"Height":2160,"Uri":"//store-images.s-microsoft.com/image/hero"},
     {"ImagePurpose":"TitledHeroArt","Width":1920,"Height":1080,"Uri":"//store-images.s-microsoft.com/image/titled"},
     {"ImagePurpose":"Screenshot","Width":1920,"Height":1080,"Uri":"//store-images.s-microsoft.com/image/s2"},
     {"ImagePurpose":"Screenshot","Width":1920,"Height":1080,"Uri":"//store-images.s-microsoft.com/image/s3"},
     {"ImagePurpose":"Screenshot","Width":1920,"Height":1080,"Uri":"//store-images.s-microsoft.com/image/s4"},
     {"ImagePurpose":"Screenshot","Width":1920,"Height":1080,"Uri":"//store-images.s-microsoft.com/image/s5"}]}]}]}
    """.utf8)

    func testXboxFindsTheGameNotItsSequelOrAddOn() {
        XCTAssertEqual(query(XboxStoreArt.suggestURL(for: "Hollow Knight™"))["query"], "Hollow Knight")
        XCTAssertEqual(XboxStoreArt.productID(in: xboxSuggest, matching: ["Hollow Knight"]), "9MW9469V91LM")
        XCTAssertNil(XboxStoreArt.productID(in: xboxSuggest, matching: ["Celeste"]))
        XCTAssertEqual(query(XboxStoreArt.productURL(id: "9MW9469V91LM"))["bigIds"], "9MW9469V91LM")
    }

    func testXboxGivesCoverBackgroundsAndASquareIcon() {
        let list = XboxStoreArt.candidates(in: xboxProduct)
        let image = "https://store-images.s-microsoft.com/image/"
        XCTAssertEqual(by(list, .cover), [image + "poster"])
        XCTAssertEqual(by(list, .background), [image + "hero", image + "titled", image + "s1", image + "s2",
                                               image + "s3", image + "s4"], "four screenshots at most")
        XCTAssertEqual(by(list, .icon), [image + "box"])
        XCTAssertEqual(by(list, .logo), [], "Xbox's logo is a store tile, not a wordmark")
        XCTAssertTrue(list.allSatisfy { $0.source.hasPrefix("Xbox Store") })
    }

    // MARK: - GOG

    private let gogSearch = Data("""
    {"products":[
     {"title":"Hollow Knight: Silksong","logo":"https://images.gog-statics.com/silk.png"},
     {"title":"Hollow Knight","logo":"https://images.gog-statics.com/logo.png",
      "coverVertical":"https://images.gog-statics.com/vertical.jpg",
      "coverHorizontal":"https://images.gog-statics.com/horizontal.png",
      "galaxyBackgroundImage":"https://images.gog-statics.com/galaxy.jpg",
      "screenshots":["https://images.gog-statics.com/s1_{formatter}.jpg","https://images.gog-statics.com/s2_{formatter}.jpg"]}]}
    """.utf8)

    func testGOGGivesItsLogoCoversAndScreenshots() {
        XCTAssertEqual(query(GOGArt.searchURL(for: "Hollow Knight"))["query"], "like:Hollow Knight")
        let list = GOGArt.candidates(in: gogSearch, matching: ["Hollow Knight"])
        XCTAssertEqual(by(list, .logo), ["https://images.gog-statics.com/logo.png"])
        XCTAssertEqual(by(list, .cover), ["https://images.gog-statics.com/vertical.jpg"])
        XCTAssertEqual(by(list, .background), ["https://images.gog-statics.com/galaxy.jpg",
                                               "https://images.gog-statics.com/horizontal.png",
                                               "https://images.gog-statics.com/s1.jpg",
                                               "https://images.gog-statics.com/s2.jpg"], "screenshots at full size")
        XCTAssertEqual(GOGArt.candidates(in: gogSearch, matching: ["Celeste"]), [])
    }

    // MARK: - Nintendo Europe

    private let europeSearch = Data("""
    {"response":{"docs":[
     {"title":"Ni No Kuni Remastered","image_url_h2x1_s":"https://www.nintendo.com/eu/media/images/H2x1_NiNoKuni_image500w.jpg"},
     {"title":"Celeste","image_url_sq_s":"https://www.nintendo.com/eu/media/images/SQ_Celeste_image500w.jpg",
      "image_url_h2x1_s":"https://www.nintendo.com/eu/media/images/H2x1_Celeste_image500w.jpg"}]}}
    """.utf8)

    func testNintendoEuropeGivesItsBannerLargeAndItsSquare() {
        let url = NintendoEuropeArt.searchURL(for: "Celeste™")
        XCTAssertEqual(query(url)["q"], "Celeste")
        XCTAssertTrue(query(url)["fq"]?.contains("nintendoswitch") == true)
        let list = NintendoEuropeArt.candidates(in: europeSearch, matching: ["Celeste"])
        let background = list.first { $0.slot == .background }
        XCTAssertEqual(background?.url.absoluteString, "https://www.nintendo.com/eu/media/images/H2x1_Celeste_image1600w.jpg")
        XCTAssertEqual(background?.fallback?.absoluteString, "https://www.nintendo.com/eu/media/images/H2x1_Celeste_image500w.jpg")
        XCTAssertEqual(by(list, .icon), ["https://www.nintendo.com/eu/media/images/SQ_Celeste_image500w.jpg"])
        XCTAssertEqual(NintendoEuropeArt.candidates(in: europeSearch, matching: ["Hades"]), [])
    }

    // MARK: - Steam screenshots

    func testSteamScreenshotsAtFullSize() {
        XCTAssertEqual(query(SteamStoreArt.screenshotsURL(appID: 367520))["appids"], "367520")
        let data = Data("""
        {"367520":{"success":true,"data":{"screenshots":[
         {"id":0,"path_full":"https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/367520/ss_a.1920x1080.jpg?t=1"},
         {"id":1,"path_full":"https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/367520/ss_b.1920x1080.jpg?t=1"}]}}}
        """.utf8)
        let list = SteamStoreArt.screenshots(in: data, appID: 367520)
        XCTAssertEqual(list.map(\.slot), [.background, .background])
        XCTAssertEqual(list.first?.source, "Steam screenshot 1")
        XCTAssertEqual(list.first?.url.lastPathComponent, "ss_a.1920x1080.jpg")
        XCTAssertEqual(SteamStoreArt.screenshots(in: Data("{}".utf8), appID: 1), [])
    }

    // MARK: - Wikidata

    func testWikidataGivesTheLogoAndTheSteamIDOfTheVideoGame() {
        XCTAssertEqual(query(WikidataArt.searchURL(for: "Hollow Knight™"))["search"], "Hollow Knight")
        let search = Data("""
        {"search":[{"id":"Q123017178","label":"Hollow Knight","description":"video game series"},
                   {"id":"Q29300592","label":"Hollow Knight","description":"2017 video game"},
                   {"id":"Q63294487","label":"Hollow Knight: Silksong"}]}
        """.utf8)
        XCTAssertEqual(WikidataArt.ids(in: search, matching: ["Hollow Knight"]), ["Q123017178", "Q29300592"])
        XCTAssertEqual(query(WikidataArt.entitiesURL(ids: ["Q1", "Q2"]))["ids"], "Q1|Q2")
        let entities = Data("""
        {"entities":{
         "Q123017178":{"claims":{"P31":[{"mainsnak":{"datavalue":{"value":{"id":"Q7058673"}}}}],
                                 "P154":[{"mainsnak":{"datavalue":{"value":"Series logo.svg"}}}]}},
         "Q29300592":{"claims":{"P31":[{"mainsnak":{"datavalue":{"value":{"id":"Q7889"}}}}],
                                "P154":[{"mainsnak":{"datavalue":{"value":"Hollow Knight logo.svg"}}},
                                        {"mainsnak":{"datavalue":{"value":"Hollow Knight text-only logo black.svg"}}}],
                                "P1733":[{"mainsnak":{"datavalue":{"value":"367520"}}}]}}}}
        """.utf8)
        let found = WikidataArt.parse(entities, order: ["Q123017178", "Q29300592"])
        XCTAssertEqual(found.steamAppID, 367520)
        XCTAssertEqual(found.logos.map(\.absoluteString),
                       ["https://commons.wikimedia.org/wiki/Special:FilePath/Hollow_Knight_logo.svg?width=1600"],
                       "a video game's logo only, never a black one")
    }

    // MARK: - TheGamesDB

    private let gamesDBSearch = """
    <a href="./game.php?id=105796"><div class="card"><img src="x"><div class="card-footer bg-secondary">
      <p>Hollow Knight: Silksong</p><p class="text-muted">Nintendo Switch</p></div></div></a>
    <a href="./game.php?id=56105"><div class="card"><img src="x"><div class="card-footer bg-secondary">
      <p>Hollow Knight</p><p>NTSC</p><p class="text-muted">Nintendo Switch</p></div></div></a>
    """

    private let gamesDBGame = """
    <a href="https://cdn.thegamesdb.net/images/original/boxart/front/56105-1.jpg"><img src="https://cdn.thegamesdb.net/images/thumb/boxart/front/56105-1.jpg"></a>
    <a href="https://cdn.thegamesdb.net/images/original/clearlogo/56105-1.png">logo</a>
    <a href="https://cdn.thegamesdb.net/images/original/fanart/56105-1.jpg">fanart</a>
    <a href="https://cdn.thegamesdb.net/images/original/screenshot/56105-1.jpg"></a>
    <a href="https://cdn.thegamesdb.net/images/original/screenshot/56105-2.jpg"></a>
    <a href="https://cdn.thegamesdb.net/images/original/screenshot/56105-1.jpg"></a>
    <a href="https://cdn.thegamesdb.net/images/original/screenshot/56105-3.jpg"></a>
    <a href="https://cdn.thegamesdb.net/images/original/screenshot/56105-4.jpg"></a>
    <a href="https://cdn.thegamesdb.net/images/original/screenshot/56105-5.jpg"></a>
    <a href="https://cdn.thegamesdb.net/images/original/clearlogo/99999-1.png">another game</a>
    """

    func testTheGamesDBSearchesSwitchGamesAndTakesTheSameName() {
        let url = TheGamesDBArt.searchURL(for: "Hollow Knight™")
        XCTAssertEqual(query(url)["name"], "Hollow Knight")
        XCTAssertEqual(query(url)["platform_id[]"], "4971", "Nintendo Switch")
        XCTAssertEqual(TheGamesDBArt.gameID(in: gamesDBSearch, matching: ["Hollow Knight"]), 56105)
        XCTAssertNil(TheGamesDBArt.gameID(in: gamesDBSearch, matching: ["Celeste"]))
        XCTAssertEqual(TheGamesDBArt.gameURL(id: 56105).absoluteString, "https://thegamesdb.net/game.php?id=56105")
    }

    func testTheGamesDBGivesItsClearLogoCoverFanartAndScreenshots() {
        let list = TheGamesDBArt.candidates(in: gamesDBGame, id: 56105)
        let base = "https://cdn.thegamesdb.net/images/original/"
        XCTAssertEqual(by(list, .logo), [base + "clearlogo/56105-1.png"])
        XCTAssertEqual(by(list, .cover), [base + "boxart/front/56105-1.jpg"])
        XCTAssertEqual(by(list, .background), [base + "fanart/56105-1.jpg", base + "screenshot/56105-1.jpg",
                                               base + "screenshot/56105-2.jpg", base + "screenshot/56105-3.jpg",
                                               base + "screenshot/56105-4.jpg"])
        XCTAssertTrue(list.allSatisfy { $0.source.hasPrefix("TheGamesDB") })
    }

    // MARK: - Fan wikis

    func testFanWikisAreSearchedLikeCommons() {
        XCTAssertFalse(MediaWikiLogos.fanWikis.isEmpty)
        let pikmin = MediaWikiLogos.fanWikis.first { $0.source == "Pikipedia" }!
        let url = pikmin.searchURL(for: "Pikmin 4")
        XCTAssertEqual(url?.host, "www.pikminwiki.com")
        XCTAssertEqual(query(url)["gsrsearch"], "Pikmin 4 logo")
        let data = Data("""
        {"query":{"pages":[
         {"title":"File:Pikmin 4 Logo.png","index":1,"imageinfo":[{"mime":"image/png","width":900,"url":"https://pikmin.wiki.gallery/images/a/a1/Pikmin_4_Logo.png"}]},
         {"title":"File:Pikmin 4 Japanese logo.png","index":2,"imageinfo":[{"mime":"image/png","width":900,"url":"https://pikmin.wiki.gallery/j.png"}]},
         {"title":"File:Pikmin 4 Logo with background.jpg","index":3,"imageinfo":[{"mime":"image/jpeg","width":900,"url":"https://pikmin.wiki.gallery/b.jpg"}]}]}}
        """.utf8)
        XCTAssertEqual(MediaWikiLogos.parse(data, gameNames: ["Pikmin 4"]).map(\.lastPathComponent), ["Pikmin_4_Logo.png"])
    }

    // MARK: - Wallhaven

    func testWallhavenGivesFourBackgroundsForTheGamesName() {
        let url = WallhavenGameArt.searchURL(for: "Hollow Knight™")
        XCTAssertEqual(query(url)["q"], "Hollow Knight")
        XCTAssertEqual(query(url)["purity"], "100")
        let items = (1...6).map { i in
            #"{"id":"w\#(i)","url":"https://wallhaven.cc/w/w\#(i)","purity":"sfw","category":"general","dimension_x":3840,"dimension_y":2160,"path":"https://w.wallhaven.cc/full/w\#(i).jpg","thumbs":{"large":"https://th.wallhaven.cc/lg/w\#(i).jpg"}}"#
        }
        let data = Data(#"{"data":[\#(items.joined(separator: ","))],"meta":{"current_page":1,"last_page":1}}"#.utf8)
        let list = WallhavenGameArt.candidates(in: data)
        XCTAssertEqual(list.count, 4)
        XCTAssertEqual(list.first?.url.absoluteString, "https://w.wallhaven.cc/full/w1.jpg")
        XCTAssertEqual(list.first?.source, "Wallhaven")
        XCTAssertEqual(Set(list.map(\.slot)), [.background])
    }

    // MARK: - All together

    func testThePickerKeepsEachSlotsOnlineArtInSourceOrder() {
        let logo = ArtworkCandidate(slot: .logo, source: "Steam", url: URL(string: "https://a/logo.png")!)
        let hero = ArtworkCandidate(slot: .background, source: "Xbox Store", url: URL(string: "https://a/hero.jpg")!)
        let again = ArtworkCandidate(slot: .logo, source: "GOG", url: URL(string: "https://a/logo.png")!)
        let store = URL(string: "https://img.example/logo.png")!
        let logos = ArtworkCandidates.list(for: .logo, entries: [], titleDB: nil, storeHeader: nil, storeImage: nil,
                                           storeLogo: store, online: [logo, hero, again])
        XCTAssertEqual(logos.map(\.source), ["Nintendo store", "Steam"], "no other slot, no duplicate")
    }

    func testFindAsksEverySourceAndFallsBackToWikidatasSteamID() async {
        let client = RoutedClient()
        let names = ["Hollow Knight"]
        // Steam's own search misses; Wikidata knows the Steam app.
        client.routes[WikidataArt.searchURL(for: "Hollow Knight")!.absoluteString] = Data("""
        {"search":[{"id":"Q29300592","label":"Hollow Knight"}]}
        """.utf8)
        client.routes[WikidataArt.entitiesURL(ids: ["Q29300592"])!.absoluteString] = Data("""
        {"entities":{"Q29300592":{"claims":{"P31":[{"mainsnak":{"datavalue":{"value":{"id":"Q7889"}}}}],
         "P1733":[{"mainsnak":{"datavalue":{"value":"367520"}}}]}}}}
        """.utf8)
        client.routes[GOGArt.searchURL(for: "Hollow Knight")!.absoluteString] = gogSearch
        let list = await OnlineArtwork.find(names: names, slot: .logo, client: client)
        XCTAssertEqual(list.map(\.source), ["Steam", "GOG"])
        XCTAssertEqual(list.first?.url.absoluteString,
                       "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/367520/logo_2x.png")
    }
}
