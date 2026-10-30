import XCTest
@testable import NXLibraryCore

final class OnlineLiveSourcesTests: XCTestCase {
    private func query(_ url: URL?) -> [String: String] {
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - MotionBGs

    // Trimmed from real listing pages: three tiles' markup, no images.
    private func listing(next: Bool) -> String {
        """
        <div class=tmb><a title="A Galaxy Within live wallpaper" href=/a-galaxy-within> <figure><picture>\
        <source srcset=/i/c/364x205/media/10270/a-galaxy-within.3840x2160.jpg.webp type=image/webp>\
        <img alt="a galaxy within live wallpaper" height=205 src=/i/c/364x205/media/10270/a-galaxy-within.3840x2160.jpg width=364>\
        </picture></figure> <span class=ttl>A Galaxy Within</span> <span class=frm> 4K </span> </a>\
        <a title="Kokomi&#39;s Serene Sea live wallpaper" href=/kokomis-serene-sea> <figure><picture>\
        <img alt="kokomi's serene sea live wallpaper" height=205 src=/i/c/364x205/media/1640/kokomis-serene-sea.jpg width=364>\
        </picture></figure> <span class=ttl>Kokomi&#39;s Serene Sea &amp; Sky</span> <span class=frm> HD </span> </a>\
        <a title="Phone live wallpaper" href=/phone-thing> <figure><picture>\
        <img alt="" height=205 src=/i/c/364x205/media/77/phone-thing.jpg width=364>\
        </picture></figure> <span class=ttl>Phone thing</span> <span class=frm> Mobile </span> </a></div>
        \(next ? "<link href=https://motionbgs.com/4k/2/ rel=next>" : "")
        """
    }

    func testMotionBGsListingAddresses() {
        let categories = MotionBGsAPI.categories
        XCTAssertEqual(categories.map(\.id), ["latest", "4k", "anime", "games", BackgroundCategory.searchID])
        XCTAssertEqual(MotionBGsAPI.listingURL(categories[0], query: nil, page: 1)?.absoluteString, "https://motionbgs.com/")
        XCTAssertEqual(MotionBGsAPI.listingURL(categories[0], query: nil, page: 3)?.absoluteString, "https://motionbgs.com/3/")
        XCTAssertEqual(MotionBGsAPI.listingURL(categories[1], query: nil, page: 1)?.absoluteString, "https://motionbgs.com/4k/")
        XCTAssertEqual(MotionBGsAPI.listingURL(categories[2], query: nil, page: 2)?.absoluteString,
                       "https://motionbgs.com/tag:anime/2/")
        XCTAssertEqual(MotionBGsAPI.listingURL(categories[3], query: nil, page: 1)?.absoluteString,
                       "https://motionbgs.com/tag:games/")
    }

    func testMotionBGsSearchNeedsWordsAndPagesByParameter() {
        let search = MotionBGsAPI.categories.last!
        XCTAssertNil(MotionBGsAPI.listingURL(search, query: " ", page: 1))
        XCTAssertEqual(query(MotionBGsAPI.listingURL(search, query: "genshin impact", page: 1))["q"], "genshin impact")
        XCTAssertNil(query(MotionBGsAPI.listingURL(search, query: "genshin", page: 1))["page"])
        XCTAssertEqual(query(MotionBGsAPI.listingURL(search, query: "genshin", page: 2))["page"], "2")
        XCTAssertEqual(MotionBGsAPI.listingURL(search, query: "zelda", page: 1)?.path, "/search")
    }

    func testMotionBGsParsesDesktopTilesAndResolvesTheirFiles() {
        let page = MotionBGsAPI.parseListing(listing(next: true))
        XCTAssertEqual(page.items.map(\.id), ["motionbgs-10270", "motionbgs-1640"], "a phone wallpaper never shows")
        XCTAssertTrue(page.hasMore)
        let galaxy = page.items[0]
        XCTAssertEqual(galaxy.kind, .video)
        XCTAssertEqual(galaxy.title, "A Galaxy Within")
        XCTAssertEqual(galaxy.width, 3840)
        XCTAssertEqual(galaxy.height, 2160)
        XCTAssertEqual(galaxy.pageURL.absoluteString, "https://motionbgs.com/a-galaxy-within")
        XCTAssertEqual(galaxy.thumbnailURL.absoluteString,
                       "https://motionbgs.com/i/c/546x308/media/10270/a-galaxy-within.3840x2160.jpg")
        XCTAssertEqual(galaxy.fileURL?.absoluteString, "https://motionbgs.com/dl/4k/10270/")
        let sea = page.items[1]
        XCTAssertEqual(sea.title, "Kokomi's Serene Sea & Sky")
        XCTAssertEqual(sea.width, 1920)
        XCTAssertEqual(sea.fileURL?.absoluteString, "https://motionbgs.com/dl/hd/1640/")
        XCTAssertEqual(OnlineDownload.fileName(for: galaxy, fileURL: galaxy.fileURL!), "motionbgs-10270.mp4")
        XCTAssertEqual(OnlineDownload.wallpaperID(for: galaxy), "live/motionbgs-10270")
    }

    func testMotionBGsLastPageHasNoMore() {
        XCTAssertFalse(MotionBGsAPI.parseListing(listing(next: false)).hasMore)
        XCTAssertEqual(MotionBGsAPI.parseListing("<html>changed layout</html>").items, [])
    }

    // MARK: - Steam

    private let steamQuery = Data("""
    {"response":{"definitions":[
     {"appid":1263950,"defid":78810,"community_item_class":3,
      "community_item_data":{"item_title":"Black Hole","item_image_large":"da53.jpg",
       "item_movie_mp4":"2489.mp4","item_movie_mp4_small":"9f3c.mp4","animated":true}},
     {"appid":2692280,"defid":4109737,"community_item_class":3,
      "community_item_data":{"item_title":"Behind the Club Lights","item_image_large":"84ad.jpg","animated":false}},
     {"appid":795040,"defid":5,"community_item_class":3,
      "community_item_data":{"item_title":"No movie","item_image_large":"x.jpg","animated":true}}
    ],"total_count":1648,"count":3,"next_cursor":"AoJUAl2TOw=="}}
    """.utf8)

    func testSteamAsksForAnimatedProfileBackgrounds() {
        let categories = SteamAPI.categories
        XCTAssertEqual(categories.map(\.id), ["popular", "newest", BackgroundCategory.searchID])
        let popular = query(SteamAPI.queryURL(categories[0], query: nil, cursor: nil))
        XCTAssertEqual(popular["community_item_classes[0]"], "3")
        XCTAssertEqual(popular["filters[0]"], "1", "animated only")
        XCTAssertEqual(popular["sort"], "2")
        XCTAssertEqual(popular["sort_descending"], "false")
        XCTAssertEqual(popular["count"], String(SteamAPI.pageSize))
        XCTAssertNil(popular["cursor"])
        let newest = query(SteamAPI.queryURL(categories[1], query: nil, cursor: "abc=="))
        XCTAssertNil(newest["sort"])
        XCTAssertEqual(newest["cursor"], "abc==")
        XCTAssertNil(SteamAPI.queryURL(categories[2], query: "", cursor: nil))
        XCTAssertEqual(query(SteamAPI.queryURL(categories[2], query: " cyberpunk ", cursor: nil))["search_term"], "cyberpunk")
    }

    func testSteamKeepsAnimatedItemsWithAMovie() throws {
        let result = try SteamAPI.parseQuery(steamQuery)
        XCTAssertEqual(result.page.items.map(\.id), ["steam-78810"])
        XCTAssertEqual(result.nextCursor, "AoJUAl2TOw==")
        XCTAssertTrue(result.page.hasMore)
        let hole = result.page.items[0]
        XCTAssertEqual(hole.kind, .video)
        XCTAssertEqual(hole.title, "Black Hole")
        XCTAssertEqual(hole.thumbnailURL.absoluteString,
                       "https://shared.akamai.steamstatic.com/community_assets/images/items/1263950/da53.jpg")
        XCTAssertEqual(hole.fileURL?.absoluteString,
                       "https://shared.akamai.steamstatic.com/community_assets/images/items/1263950/2489.mp4")
        XCTAssertEqual(hole.pageURL.absoluteString, "https://store.steampowered.com/points/shop/app/1263950")
        XCTAssertEqual(SteamAPI.appID(of: hole), 1263950)
        XCTAssertEqual(ResolutionBadge.label(width: hole.width, height: hole.height), "1080p")
    }

    func testSteamEndsWithoutACursor() throws {
        let last = Data(String(decoding: steamQuery, as: UTF8.self)
            .replacingOccurrences(of: ",\"next_cursor\":\"AoJUAl2TOw==\"", with: "").utf8)
        let result = try SteamAPI.parseQuery(last)
        XCTAssertNil(result.nextCursor)
        XCTAssertFalse(result.page.hasMore)
    }

    func testSteamGameNames() throws {
        let url = SteamAPI.gameNamesURL(appIDs: [1091500])
        XCTAssertEqual(url.host, "api.steampowered.com")
        XCTAssertTrue(query(url)["input_json"]?.contains("1091500") == true)
        let names = try SteamAPI.parseGameNames(Data("""
        {"response":{"store_items":[{"appid":1091500,"name":"Cyberpunk 2077"},{"appid":0,"name":""}]}}
        """.utf8))
        XCTAssertEqual(names, [1091500: "Cyberpunk 2077"])
    }

    func testSteamCreditNamesTheGame() {
        let credit = BackgroundCredit(source: .steam, title: "Rogue AI", author: "Cyberpunk 2077",
                                      pageURL: URL(string: "https://store.steampowered.com/points/shop/app/1091500")!,
                                      width: 1920, height: 1080)
        XCTAssertEqual(credit.line, "Steam · Cyberpunk 2077")
    }

    // MARK: - The Live tab

    func testLiveSourcesHaveTheirChips() {
        XCTAssertEqual(BackgroundSourceID.motionbgs.categories, MotionBGsAPI.categories)
        XCTAssertEqual(BackgroundSourceID.steam.categories, SteamAPI.categories)
        XCTAssertEqual(OnlineBrowseState(source: .steam).category.id, "popular")
    }
}
