import XCTest
@testable import NXLibraryCore

final class OnlineBackgroundsTests: XCTestCase {
    // Trimmed from real responses: metadata only, no images.
    private let wallhavenSearch = Data("""
    {"data":[
     {"id":"qrppoq","url":"https://wallhaven.cc/w/qrppoq","purity":"sfw","category":"anime",
      "dimension_x":3840,"dimension_y":2160,"file_type":"image/png",
      "path":"https://w.wallhaven.cc/full/qr/wallhaven-qrppoq.png",
      "thumbs":{"large":"https://th.wallhaven.cc/lg/qr/qrppoq.jpg","small":"https://th.wallhaven.cc/small/qr/qrppoq.jpg"}},
     {"id":"xx11yy","url":"https://wallhaven.cc/w/xx11yy","purity":"sketchy","category":"anime",
      "dimension_x":3840,"dimension_y":2160,"file_type":"image/jpeg",
      "path":"https://w.wallhaven.cc/full/xx/wallhaven-xx11yy.jpg",
      "thumbs":{"large":"https://th.wallhaven.cc/lg/xx/xx11yy.jpg"}}
    ],
    "meta":{"current_page":1,"last_page":7,"per_page":24,"total":149}}
    """.utf8)

    private let wallhavenDetail = Data("""
    {"data":{"id":"qrppoq","uploader":{"username":"SARATDSA","group":"User"},
     "tags":[{"id":1,"name":"black background"},{"id":2,"name":"minimalism"}]}}
    """.utf8)

    private func danbooruPost(id: Int, rating: String = "g", width: Int = 3840, height: Int = 2160,
                              ext: String = "jpg", file: Bool = true, deleted: Bool = false, banned: Bool = false,
                              artist: String = "the_raspy_cupcake", copyright: String = "original") -> String {
        """
        {"id":\(id),"rating":"\(rating)","image_width":\(width),"image_height":\(height),"file_ext":"\(ext)",
         \(file ? "\"file_url\":\"https://cdn.donmai.us/original/3a/28/\(id).\(ext)\"," : "")
         "large_file_url":"https://cdn.donmai.us/sample/3a/28/sample-\(id).jpg",
         "preview_file_url":"https://cdn.donmai.us/180x180/3a/28/\(id).jpg",
         "tag_string_artist":"\(artist)","tag_string_copyright":"\(copyright)",
         "is_deleted":\(deleted),"is_banned":\(banned)}
        """
    }

    // MARK: - Wallhaven

    private func query(_ url: URL?) -> [String: String] {
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testWallhavenAlwaysAsksForSafeWideAndAtLeast2K() {
        for category in WallhavenAPI.categories where !category.isSearch {
            let q = query(WallhavenAPI.searchURL(category, query: nil, page: 3))
            XCTAssertEqual(q["purity"], "100", category.id)
            XCTAssertEqual(q["atleast"], "2560x1440")
            XCTAssertEqual(q["ratios"], "16x9")
            XCTAssertEqual(q["page"], "3")
        }
        let featured = query(WallhavenAPI.searchURL(WallhavenAPI.categories[0], query: nil, page: 1))
        XCTAssertEqual(featured["sorting"], "toplist")
        XCTAssertEqual(featured["topRange"], "1M")
        XCTAssertEqual(featured["categories"], "111")
        let anime = WallhavenAPI.categories.first { $0.id == "anime" }!
        XCTAssertEqual(query(WallhavenAPI.searchURL(anime, query: nil, page: 1))["categories"], "010")
    }

    func testWallhavenSearchNeedsAQuery() {
        let search = WallhavenAPI.categories.first(where: \.isSearch)!
        XCTAssertNil(WallhavenAPI.searchURL(search, query: nil, page: 1))
        XCTAssertNil(WallhavenAPI.searchURL(search, query: "   ", page: 1))
        let q = query(WallhavenAPI.searchURL(search, query: " elden ring ", page: 1))
        XCTAssertEqual(q["q"], "elden ring")
        XCTAssertEqual(q["sorting"], "relevance")
        XCTAssertEqual(q["purity"], "100")
    }

    func testWallhavenParsesSafeItemsAndPaging() throws {
        let page = try WallhavenAPI.parseSearch(wallhavenSearch)
        XCTAssertEqual(page.items.map(\.id), ["wallhaven-qrppoq"], "sketchy never shows")
        XCTAssertTrue(page.hasMore)
        let item = page.items[0]
        XCTAssertEqual(item.source, .wallhaven)
        XCTAssertEqual(item.sourceID, "qrppoq")
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(item.width, 3840)
        XCTAssertEqual(item.height, 2160)
        XCTAssertEqual(item.thumbnailURL.absoluteString, "https://th.wallhaven.cc/lg/qr/qrppoq.jpg")
        XCTAssertEqual(item.pageURL.absoluteString, "https://wallhaven.cc/w/qrppoq")
        XCTAssertEqual(item.fileURL?.absoluteString, "https://w.wallhaven.cc/full/qr/wallhaven-qrppoq.png")
        XCTAssertEqual(item.title, "Anime")
        XCTAssertNil(item.previewURL, "a still has no moving preview")
    }

    func testWallhavenLastPageHasNoMore() throws {
        let last = Data(String(decoding: wallhavenSearch, as: UTF8.self)
            .replacingOccurrences(of: "\"current_page\":1", with: "\"current_page\":7").utf8)
        XCTAssertFalse(try WallhavenAPI.parseSearch(last).hasMore)
    }

    func testWallhavenDetailGivesUploaderAndTitle() throws {
        XCTAssertEqual(WallhavenAPI.detailURL(sourceID: "qrppoq").absoluteString, "https://wallhaven.cc/api/v1/w/qrppoq")
        let detail = try WallhavenAPI.parseDetail(wallhavenDetail)
        XCTAssertEqual(detail.author, "SARATDSA")
        XCTAssertEqual(detail.title, "Black background")
    }

    // MARK: - Danbooru

    private func tags(_ url: URL?) -> [String] {
        (query(url)["tags"] ?? "").split(separator: " ").map(String.init)
    }

    func testDanbooruAlwaysAsksForGeneralWideAndAtLeast2K() {
        for category in DanbooruAPI.categories where !category.isSearch {
            let t = tags(DanbooruAPI.postsURL(category, query: nil, page: 2))
            XCTAssertTrue(t.contains("rating:g"), category.id)
            XCTAssertTrue(t.contains("ratio:16:9"))
            XCTAssertTrue(t.contains("width:>=2560"))
            XCTAssertLessThanOrEqual(t.filter { !$0.contains(":") }.count, 2,
                                     "anonymous searches count only two plain tags")
            XCTAssertEqual(query(DanbooruAPI.postsURL(category, query: nil, page: 2))["page"], "2")
            XCTAssertEqual(query(DanbooruAPI.postsURL(category, query: nil, page: 2))["limit"],
                           String(DanbooruAPI.pageSize))
        }
        XCTAssertEqual(tags(DanbooruAPI.postsURL(DanbooruAPI.categories[0], query: nil, page: 1))
                        .filter { !$0.contains(":") }, ["scenery", "no_humans"])
    }

    func testDanbooruSearchIsOneTagOfScenery() {
        let search = DanbooruAPI.categories.first(where: \.isSearch)!
        XCTAssertNil(DanbooruAPI.postsURL(search, query: "", page: 1))
        let t = tags(DanbooruAPI.postsURL(search, query: "Genshin Impact", page: 1))
        XCTAssertEqual(t.filter { !$0.contains(":") }, ["genshin_impact", "no_humans"])
        XCTAssertTrue(t.contains("rating:g"))
        // A typed metatag cannot loosen the rating.
        let sneaky = tags(DanbooruAPI.postsURL(search, query: "rating:e", page: 1))
        XCTAssertFalse(sneaky.contains("rating:e"))
        XCTAssertTrue(sneaky.contains("rating:g"))
    }

    func testDanbooruKeepsOnlyGeneralWideStillsItCanShow() throws {
        let posts = [
            danbooruPost(id: 1),
            danbooruPost(id: 2, rating: "s"),
            danbooruPost(id: 3, file: false),
            danbooruPost(id: 4, deleted: true),
            danbooruPost(id: 5, banned: true),
            danbooruPost(id: 6, width: 2000, height: 1125),
            danbooruPost(id: 7, width: 3840, height: 3000),
            danbooruPost(id: 8, ext: "mp4"),
            danbooruPost(id: 9, ext: "png", artist: "", copyright: "genshin_impact honkai:_star_rail"),
        ]
        let page = try DanbooruAPI.parsePosts(Data("[\(posts.joined(separator: ","))]".utf8))
        XCTAssertEqual(page.items.map(\.id), ["danbooru-1", "danbooru-9"])
        XCTAssertFalse(page.hasMore, "fewer than a page came back")
        let first = page.items[0]
        XCTAssertEqual(first.author, "the raspy cupcake")
        XCTAssertEqual(first.title, "Original")
        XCTAssertEqual(first.pageURL.absoluteString, "https://danbooru.donmai.us/posts/1")
        XCTAssertEqual(first.thumbnailURL.absoluteString, "https://cdn.donmai.us/sample/3a/28/sample-1.jpg")
        XCTAssertEqual(first.fileURL?.absoluteString, "https://cdn.donmai.us/original/3a/28/1.jpg")
        XCTAssertNil(page.items[1].author)
        XCTAssertEqual(page.items[1].title, "Genshin impact")
    }

    func testDanbooruFullPageHasMore() throws {
        let posts = (1...DanbooruAPI.pageSize).map { danbooruPost(id: $0, rating: $0 == 1 ? "q" : "g") }
        let page = try DanbooruAPI.parsePosts(Data("[\(posts.joined(separator: ","))]".utf8))
        XCTAssertTrue(page.hasMore, "a full page, even after filtering, means there may be more")
        XCTAssertEqual(page.items.count, DanbooruAPI.pageSize - 1)
    }

    // MARK: - Badges, files, credits

    func testResolutionBadges() {
        XCTAssertEqual(ResolutionBadge.label(width: 7680, height: 4320), "8K")
        XCTAssertEqual(ResolutionBadge.label(width: 5120, height: 2880), "5K")
        XCTAssertEqual(ResolutionBadge.label(width: 3840, height: 2160), "4K")
        XCTAssertEqual(ResolutionBadge.label(width: 3696, height: 2079), "2K")
        XCTAssertEqual(ResolutionBadge.label(width: 2560, height: 1440), "2K")
        XCTAssertEqual(ResolutionBadge.label(width: 1920, height: 1080), "1080p")
    }

    func testDownloadedFileKeepsSourceIDAndExtension() throws {
        let item = try WallhavenAPI.parseSearch(wallhavenSearch).items[0]
        let file = item.fileURL!
        XCTAssertEqual(OnlineDownload.fileName(for: item, fileURL: file), "wallhaven-qrppoq.png")
        XCTAssertEqual(OnlineDownload.folder(for: .image), WallpaperCatalog.online)
        XCTAssertEqual(OnlineDownload.folder(for: .video), WallpaperCatalog.live)
        XCTAssertEqual(OnlineDownload.wallpaperID(for: item), "online/wallhaven-qrppoq")
        // An odd extension falls back to the kind's own.
        XCTAssertEqual(OnlineDownload.fileName(for: item, fileURL: URL(string: "https://x.test/file")!),
                       "wallhaven-qrppoq.jpg")
    }

    func testRemoteIdentifiersCannotBecomeDownloadPaths() {
        let folder = URL(fileURLWithPath: "/tmp/Wallpapers/online")
        let file = URL(string: "https://example.invalid/wallpaper.jpg")!
        for id in ["x/../../escaped", "../escape", "/absolute", "a\\b", "", String(repeating: "x", count: 400)] {
            let item = OnlineBackground(source: .wallhaven, sourceID: id, kind: .image,
                title: "Fixture", author: nil, width: 2560, height: 1440,
                thumbnailURL: file, pageURL: file, fileURL: file)
            let name = OnlineDownload.fileName(for: item, fileURL: file)
            let destination = folder.appendingPathComponent(name).standardizedFileURL
            XCTAssertEqual(destination.deletingLastPathComponent().path, folder.path, id)
            XCTAssertFalse(name.contains("/"), id)
            XCTAssertFalse(name.contains("\\"), id)
            XCTAssertLessThan(name.utf8.count, 200)
            XCTAssertEqual(OnlineDownload.wallpaperID(for: item), "online/" + String(name.dropLast(4)))
        }
    }

    func testCreditLines() {
        let page = URL(string: "https://wallhaven.cc/w/qrppoq")!
        XCTAssertEqual(BackgroundCredit(source: .wallhaven, title: "x", author: "SARATDSA", pageURL: page,
                                        width: 1, height: 1).line, "Wallhaven · uploaded by SARATDSA")
        XCTAssertEqual(BackgroundCredit(source: .danbooru, title: "x", author: "kazu", pageURL: page,
                                        width: 1, height: 1).line, "Danbooru · art by kazu")
        XCTAssertEqual(BackgroundCredit(source: .danbooru, title: "x", author: nil, pageURL: page,
                                        width: 1, height: 1).line, "Danbooru")
    }

    func testCreditsSurviveASaveAndAMissingFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(BackgroundCredits.fileName)
        XCTAssertEqual(BackgroundCredits.load(from: file), [:])
        let credit = BackgroundCredit(source: .danbooru, title: "Original", author: "kazu",
                                      pageURL: URL(string: "https://danbooru.donmai.us/posts/1")!, width: 3840, height: 2160)
        try BackgroundCredits.save(["online/danbooru-1": credit], to: file)
        XCTAssertEqual(BackgroundCredits.load(from: file), ["online/danbooru-1": credit])
    }

    // MARK: - Browsing a source

    private func items(_ count: Int, from start: Int = 0) -> [OnlineBackground] {
        (start..<start + count).map {
            OnlineBackground(source: .danbooru, sourceID: "\($0)", kind: .image, title: "t", author: nil,
                             width: 3840, height: 2160,
                             thumbnailURL: URL(string: "https://x.test/\($0).jpg")!,
                             pageURL: URL(string: "https://x.test/\($0)")!,
                             fileURL: URL(string: "https://x.test/\($0).png")!)
        }
    }

    func testBrowsingOpensOnTheFirstCategoryAndWantsAPage() {
        let state = OnlineBrowseState(source: .wallhaven)
        XCTAssertEqual(state.category, WallhavenAPI.categories[0])
        XCTAssertEqual(state.focus, .chips)
        XCTAssertEqual(state.nextPage, 1)
        XCTAssertTrue(state.wantsMore)
    }

    func testChipsChangeTheCategoryAndStartOver() {
        var state = OnlineBrowseState(source: .danbooru)
        state.append(OnlinePage(items: items(6), hasMore: true))
        XCTAssertFalse(state.move(.left), "already on the first chip")
        XCTAssertTrue(state.move(.right))
        XCTAssertEqual(state.categoryIndex, 1)
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertEqual(state.nextPage, 1)
        XCTAssertTrue(state.wantsMore)
        state.categoryIndex = state.categories.count - 1
        XCTAssertFalse(state.move(.right), "already on the last chip")
    }

    func testDownFromTheChipsReachesTheGridAndUpComesBack() {
        var state = OnlineBrowseState(source: .danbooru)
        XCTAssertFalse(state.move(.down), "nothing loaded yet")
        state.append(OnlinePage(items: items(7), hasMore: false))
        XCTAssertTrue(state.move(.down))
        XCTAssertEqual(state.focus, .tile(0))
        XCTAssertTrue(state.move(.right))
        XCTAssertTrue(state.move(.down))
        XCTAssertEqual(state.focus, .tile(4))
        XCTAssertTrue(state.move(.up))
        XCTAssertTrue(state.move(.up))
        XCTAssertEqual(state.focus, .chips)
        XCTAssertEqual(state.categoryIndex, 0, "coming back up does not change the category")
    }

    func testTheNextPageLoadsAsTheFocusNearsTheEnd() {
        var state = OnlineBrowseState(source: .danbooru)
        state.append(OnlinePage(items: items(24), hasMore: true))
        XCTAssertEqual(state.nextPage, 2)
        state.focus = .tile(3)
        XCTAssertFalse(state.wantsMore)
        state.focus = .tile(24 - 2 * OnlineBrowseState.columns)
        XCTAssertTrue(state.wantsMore)
        state.append(OnlinePage(items: items(24, from: 20), hasMore: false))
        XCTAssertEqual(state.items.count, 44, "a repeat from a shifted page is dropped")
        XCTAssertFalse(state.wantsMore)
    }

    func testSearchWaitsForWords() {
        var state = OnlineBrowseState(source: .wallhaven)
        state.categoryIndex = state.categories.firstIndex(where: \.isSearch)!
        XCTAssertFalse(state.wantsMore, "no words, no request")
        state.search("  aurora ")
        XCTAssertEqual(state.query, "aurora")
        XCTAssertTrue(state.wantsMore)
        XCTAssertEqual(state.focus, .chips)
    }

    func testFocusedItem() {
        var state = OnlineBrowseState(source: .danbooru)
        XCTAssertNil(state.focusedItem)
        state.append(OnlinePage(items: items(3), hasMore: false))
        state.focus = .tile(2)
        XCTAssertEqual(state.focusedItem?.id, "danbooru-2")
    }
}
