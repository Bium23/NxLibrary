import Foundation

/// Where an online background comes from.
public enum BackgroundSourceID: String, CaseIterable, Codable, Sendable {
    case wallhaven, danbooru, motionbgs, steam

    public var title: String {
        switch self {
        case .wallhaven: return "Wallhaven"
        case .danbooru: return "Danbooru"
        case .motionbgs: return "MotionBGs"
        case .steam: return "Steam"
        }
    }

    /// Stills on the Wallpapers tab, videos on Live.
    public var kind: BackgroundKind {
        switch self {
        case .wallhaven, .danbooru: return .image
        case .motionbgs, .steam: return .video
        }
    }

    /// The source's ready categories, shown as chips above its grid.
    public var categories: [BackgroundCategory] {
        switch self {
        case .wallhaven: return WallhavenAPI.categories
        case .danbooru: return DanbooruAPI.categories
        case .motionbgs: return MotionBGsAPI.categories
        case .steam: return SteamAPI.categories
        }
    }
}

/// One chip above a source's grid. "search" asks for the player's words.
public struct BackgroundCategory: Equatable, Hashable, Sendable {
    public static let searchID = "search"
    public let id: String
    public let title: String
    public var isSearch: Bool { id == Self.searchID }

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// One item of a source's listing: enough for a tile, a credit and the download.
public struct OnlineBackground: Equatable, Hashable, Identifiable, Sendable {
    public let source: BackgroundSourceID
    /// The source's own id ("qrppoq" on Wallhaven).
    public let sourceID: String
    public let kind: BackgroundKind
    public let title: String
    public let author: String?
    public let width: Int
    public let height: Int
    public let thumbnailURL: URL
    public let pageURL: URL
    /// nil when the source resolves the file on choice.
    public let fileURL: URL?

    /// "<source>-<source id>", also the downloaded file's name.
    public var id: String { "\(source.rawValue)-\(sourceID)" }

    public init(source: BackgroundSourceID, sourceID: String, kind: BackgroundKind, title: String, author: String?,
                width: Int, height: Int, thumbnailURL: URL, pageURL: URL, fileURL: URL?) {
        self.source = source
        self.sourceID = sourceID
        self.kind = kind
        self.title = title
        self.author = author
        self.width = width
        self.height = height
        self.thumbnailURL = thumbnailURL
        self.pageURL = pageURL
        self.fileURL = fileURL
    }
}

/// One page of a listing, and whether another may follow.
public struct OnlinePage: Equatable, Sendable {
    public let items: [OnlineBackground]
    public let hasMore: Bool

    public init(items: [OnlineBackground], hasMore: Bool) {
        self.items = items
        self.hasMore = hasMore
    }
}

/// The badge on an online tile.
public enum ResolutionBadge {
    public static func label(width: Int, height: Int) -> String {
        switch max(width, height) {
        case 7680...: return "8K"
        case 5120...: return "5K"
        case 3840...: return "4K"
        case 2560...: return "2K"
        default: return "1080p"
        }
    }
}

/// Words to a readable title: "genshin_impact" → "Genshin impact".
func readableTag(_ tag: String) -> String {
    let words = tag.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    return words.prefix(1).uppercased() + words.dropFirst()
}

// MARK: - Wallhaven

/// wallhaven.cc's JSON API. Safe for work only, 16:9, at least 2560×1440.
public enum WallhavenAPI {
    public static let categories = [
        BackgroundCategory(id: "featured", title: "Featured"),
        BackgroundCategory(id: "anime", title: "Anime"),
        BackgroundCategory(id: "games", title: "Games"),
        BackgroundCategory(id: "landscapes", title: "Landscapes"),
        BackgroundCategory(id: "space", title: "Space"),
        BackgroundCategory(id: "abstract", title: "Abstract"),
        BackgroundCategory(id: BackgroundCategory.searchID, title: "Search"),
    ]

    /// nil for Search without words.
    public static func searchURL(_ category: BackgroundCategory, query: String?, page: Int) -> URL? {
        var items: [URLQueryItem]
        switch category.id {
        case "featured":
            items = [.init(name: "categories", value: "111"), .init(name: "sorting", value: "toplist"),
                     .init(name: "topRange", value: "1M")]
        case "anime":
            items = [.init(name: "categories", value: "010"), .init(name: "sorting", value: "toplist"),
                     .init(name: "topRange", value: "1y")]
        case "games", "landscapes", "space", "abstract":
            let words = ["games": "video games", "landscapes": "landscape"][category.id] ?? category.id
            items = [.init(name: "q", value: words), .init(name: "categories", value: "111"),
                     .init(name: "sorting", value: "favorites")]
        default:
            let words = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else { return nil }
            items = [.init(name: "q", value: words), .init(name: "categories", value: "111"),
                     .init(name: "sorting", value: "relevance")]
        }
        var components = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        components.queryItems = items + [.init(name: "purity", value: "100"),
                                         .init(name: "atleast", value: "2560x1440"),
                                         .init(name: "ratios", value: "16x9"),
                                         .init(name: "page", value: String(page))]
        return components.url
    }

    public static func detailURL(sourceID: String) -> URL {
        URL(string: "https://wallhaven.cc/api/v1/w/")!.appendingPathComponent(sourceID)
    }

    private struct Search: Decodable {
        struct Item: Decodable {
            struct Thumbs: Decodable { let large: String? }
            let id: String
            let url: String
            let purity: String
            let category: String?
            let dimension_x: Int
            let dimension_y: Int
            let path: String
            let thumbs: Thumbs
        }
        struct Meta: Decodable { let current_page: Int; let last_page: Int }
        let data: [Item]
        let meta: Meta
    }

    public static func parseSearch(_ data: Data) throws -> OnlinePage {
        let search = try JSONDecoder().decode(Search.self, from: data)
        let items = search.data.compactMap { item -> OnlineBackground? in
            guard item.purity == "sfw", let page = URL(string: item.url), let file = URL(string: item.path),
                  let thumb = URL(string: item.thumbs.large ?? item.path) else { return nil }
            return OnlineBackground(source: .wallhaven, sourceID: item.id, kind: .image,
                                    title: readableTag(item.category ?? "Wallhaven"), author: nil,
                                    width: item.dimension_x, height: item.dimension_y,
                                    thumbnailURL: thumb, pageURL: page, fileURL: file)
        }
        return OnlinePage(items: items, hasMore: search.meta.current_page < search.meta.last_page)
    }

    private struct Detail: Decodable {
        struct Item: Decodable {
            struct Uploader: Decodable { let username: String }
            struct Tag: Decodable { let name: String }
            let uploader: Uploader?
            let tags: [Tag]?
        }
        let data: Item
    }

    /// The uploader and a title (the first tag), which the listing leaves out.
    public static func parseDetail(_ data: Data) throws -> (title: String?, author: String?) {
        let detail = try JSONDecoder().decode(Detail.self, from: data).data
        return (detail.tags?.first.map { readableTag($0.name) }, detail.uploader?.username)
    }
}

// MARK: - Danbooru

/// danbooru.donmai.us's JSON API. General rating only, 16:9, at least 2560 wide.
/// Anonymous searches count two plain tags; rating, ratio and width are free.
public enum DanbooruAPI {
    public static let pageSize = 30
    public static let categories = [
        BackgroundCategory(id: "scenery", title: "Anime scenery"),
        BackgroundCategory(id: "sky", title: "Sky"),
        BackgroundCategory(id: "city", title: "City"),
        BackgroundCategory(id: "night", title: "Night"),
        BackgroundCategory(id: BackgroundCategory.searchID, title: "Search"),
    ]
    static let fixedTags = ["rating:g", "ratio:16:9", "width:>=2560"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]

    /// nil for Search without words. Search is one tag of the player's, with no people in it.
    public static func postsURL(_ category: BackgroundCategory, query: String?, page: Int) -> URL? {
        let tags: [String]
        switch category.id {
        case "scenery": tags = ["scenery", "no_humans"]
        case "sky": tags = ["sky", "no_humans"]
        case "city": tags = ["cityscape", "no_humans"]
        case "night": tags = ["night", "no_humans"]
        default:
            // One tag from the words; a typed metatag (rating:e) loses its colon and can loosen nothing.
            let tag = (query ?? "").lowercased()
                .split { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "(" || $0 == ")") }
                .joined(separator: "_")
            guard !tag.isEmpty else { return nil }
            tags = [tag, "no_humans"]
        }
        var components = URLComponents(string: "https://danbooru.donmai.us/posts.json")!
        components.queryItems = [.init(name: "tags", value: (fixedTags + tags).joined(separator: " ")),
                                 .init(name: "limit", value: String(pageSize)),
                                 .init(name: "page", value: String(page))]
        return components.url
    }

    private struct Post: Decodable {
        let id: Int
        let rating: String?
        let image_width: Int?
        let image_height: Int?
        let file_ext: String?
        let file_url: String?
        let large_file_url: String?
        let tag_string_artist: String?
        let tag_string_copyright: String?
        let is_deleted: Bool?
        let is_banned: Bool?
    }

    public static func parsePosts(_ data: Data) throws -> OnlinePage {
        let posts = try JSONDecoder().decode([Post].self, from: data)
        let items = posts.compactMap { post -> OnlineBackground? in
            guard post.rating == "g", post.is_deleted != true, post.is_banned != true,
                  let width = post.image_width, let height = post.image_height, width >= 2560,
                  abs(Double(width) / Double(height) - 16.0 / 9) < 0.03,
                  let ext = post.file_ext?.lowercased(), imageExtensions.contains(ext),
                  let file = post.file_url.flatMap(URL.init(string:)),
                  let thumb = (post.large_file_url ?? post.file_url).flatMap(URL.init(string:)) else { return nil }
            let artist = post.tag_string_artist?.split(separator: " ").first.map { readableTag(String($0)).lowercased() }
            let title = post.tag_string_copyright?.split(separator: " ").first.map { readableTag(String($0)) }
            return OnlineBackground(source: .danbooru, sourceID: String(post.id), kind: .image,
                                    title: title ?? "Danbooru", author: artist,
                                    width: width, height: height, thumbnailURL: thumb,
                                    pageURL: URL(string: "https://danbooru.donmai.us/posts/\(post.id)")!,
                                    fileURL: file)
        }
        return OnlinePage(items: items, hasMore: posts.count >= pageSize)
    }
}

// MARK: - MotionBGs

/// motionbgs.com's pages (no API). Listings only when the player browses;
/// the file comes straight from a tile: /dl/4k/<n>/ or /dl/hd/<n>/.
public enum MotionBGsAPI {
    public static let categories = [
        BackgroundCategory(id: "latest", title: "Latest"),
        BackgroundCategory(id: "4k", title: "4K"),
        BackgroundCategory(id: "anime", title: "Anime"),
        BackgroundCategory(id: "games", title: "Games"),
        BackgroundCategory(id: BackgroundCategory.searchID, title: "Search"),
    ]
    static let site = "https://motionbgs.com"

    /// nil for Search without words. Listings page as /<path>/<n>/, search as ?page=<n>.
    public static func listingURL(_ category: BackgroundCategory, query: String?, page: Int) -> URL? {
        let paged = page > 1 ? "\(page)/" : ""
        switch category.id {
        case "latest": return URL(string: "\(site)/\(paged)")
        case "4k": return URL(string: "\(site)/4k/\(paged)")
        case "anime", "games": return URL(string: "\(site)/tag:\(category.id)/\(paged)")
        default:
            let words = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else { return nil }
            var components = URLComponents(string: "\(site)/search")!
            components.queryItems = [.init(name: "q", value: words)] + (page > 1 ? [.init(name: "page", value: String(page))] : [])
            return components.url
        }
    }

    /// The tiles of a listing page. A tile it cannot read is skipped; a page with none is empty.
    public static func parseListing(_ html: String) -> OnlinePage {
        var items: [OnlineBackground] = []
        for tile in html.components(separatedBy: "<a title=").dropFirst() {
            guard let body = tile.components(separatedBy: "</a>").first,
                  let slug = capture(#"href=/([^ >"]+)>"#, in: body),
                  let thumb = capture(#"src=/i/c/364x205/media/(\d+/[^ >"]+)"#, in: body),
                  let number = thumb.split(separator: "/").first,
                  let name = capture(#"<span class=ttl>([^<]*)</span>"#, in: body),
                  let format = capture(#"<span class=frm>\s*([^<]*?)\s*</span>"#, in: body) else { continue }
            let size: (width: Int, height: Int, folder: String)
            switch format.uppercased() {
            case "4K": size = (3840, 2160, "4k")
            case "HD": size = (1920, 1080, "hd")
            default: continue
            }
            guard let page = URL(string: "\(site)/\(slug)"),
                  let thumbnail = URL(string: "\(site)/i/c/546x308/media/\(thumb)"),
                  let file = URL(string: "\(site)/dl/\(size.folder)/\(number)/") else { continue }
            let item = OnlineBackground(source: .motionbgs, sourceID: String(number), kind: .video,
                                        title: unescape(name), author: nil, width: size.width, height: size.height,
                                        thumbnailURL: thumbnail, pageURL: page, fileURL: file)
            if !items.contains(where: { $0.id == item.id }) { items.append(item) }
        }
        let hasMore = html.contains("rel=next") || items.count >= 24
        return OnlinePage(items: items, hasMore: !items.isEmpty && hasMore)
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func unescape(_ text: String) -> String {
        [("&#39;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]
            .reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Steam

/// Steam's Points Shop animated profile backgrounds (QueryRewardItems), official
/// loops from the games' studios. Pages go by cursor.
public enum SteamAPI {
    public static let pageSize = 30
    public static let categories = [
        BackgroundCategory(id: "popular", title: "Popular"),
        BackgroundCategory(id: "newest", title: "Newest"),
        BackgroundCategory(id: BackgroundCategory.searchID, title: "Search"),
    ]
    static let media = "https://shared.akamai.steamstatic.com/community_assets/images/items"

    /// nil for Search without words. Search matches item and game names.
    public static func queryURL(_ category: BackgroundCategory, query: String?, cursor: String?) -> URL? {
        var items: [URLQueryItem] = [.init(name: "community_item_classes[0]", value: "3"),
                                     .init(name: "filters[0]", value: "1"),
                                     .init(name: "count", value: String(pageSize)),
                                     .init(name: "language", value: "english")]
        switch category.id {
        case "popular": items += [.init(name: "sort", value: "2"), .init(name: "sort_descending", value: "false")]
        case "newest": break
        default:
            let words = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else { return nil }
            items.append(.init(name: "search_term", value: words))
        }
        if let cursor { items.append(.init(name: "cursor", value: cursor)) }
        var components = URLComponents(string: "https://api.steampowered.com/ILoyaltyRewardsService/QueryRewardItems/v1/")!
        components.queryItems = items
        // "+" and "=" in a cursor must survive the query string.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    private struct Query: Decodable {
        struct Response: Decodable {
            struct Definition: Decodable {
                struct Item: Decodable {
                    let item_title: String?
                    let item_image_large: String?
                    let item_movie_mp4: String?
                    let animated: Bool?
                }
                let appid: Int
                let defid: Int
                let community_item_data: Item?
            }
            let definitions: [Definition]?
            let next_cursor: String?
        }
        let response: Response
    }

    public static func parseQuery(_ data: Data) throws -> (page: OnlinePage, nextCursor: String?) {
        let response = try JSONDecoder().decode(Query.self, from: data).response
        let definitions = response.definitions ?? []
        let items = definitions.compactMap { definition -> OnlineBackground? in
            guard let item = definition.community_item_data, item.animated == true,
                  let movie = item.item_movie_mp4, let image = item.item_image_large,
                  let file = URL(string: "\(media)/\(definition.appid)/\(movie)"),
                  let thumbnail = URL(string: "\(media)/\(definition.appid)/\(image)") else { return nil }
            return OnlineBackground(source: .steam, sourceID: String(definition.defid), kind: .video,
                                    title: item.item_title ?? "Steam", author: nil, width: 1920, height: 1080,
                                    thumbnailURL: thumbnail,
                                    pageURL: URL(string: "https://store.steampowered.com/points/shop/app/\(definition.appid)")!,
                                    fileURL: file)
        }
        let cursor = response.next_cursor.flatMap { $0.isEmpty ? nil : $0 }
        return (OnlinePage(items: items, hasMore: cursor != nil && !definitions.isEmpty), cursor)
    }

    /// The game a Steam item belongs to, from its page.
    public static func appID(of item: OnlineBackground) -> Int? {
        Int(item.pageURL.lastPathComponent)
    }

    /// IStoreBrowseService/GetItems for the games' names.
    public static func gameNamesURL(appIDs: [Int]) -> URL {
        let ids = appIDs.map { "{\"appid\":\($0)}" }.joined(separator: ",")
        var components = URLComponents(string: "https://api.steampowered.com/IStoreBrowseService/GetItems/v1/")!
        components.queryItems = [.init(name: "input_json", value:
            "{\"ids\":[\(ids)],\"context\":{\"language\":\"english\",\"country_code\":\"US\"}}")]
        return components.url!
    }

    private struct Names: Decodable {
        struct Response: Decodable {
            struct Item: Decodable { let appid: Int?; let name: String? }
            let store_items: [Item]?
        }
        let response: Response
    }

    public static func parseGameNames(_ data: Data) throws -> [Int: String] {
        var names: [Int: String] = [:]
        for item in try JSONDecoder().decode(Names.self, from: data).response.store_items ?? [] {
            if let appid = item.appid, appid != 0, let name = item.name, !name.isEmpty { names[appid] = name }
        }
        return names
    }
}

// MARK: - Downloads and credits

/// Where a chosen online background is kept: online/ for stills, live/ for videos.
public enum OnlineDownload {
    public static func folder(for kind: BackgroundKind) -> String {
        kind == .video ? WallpaperCatalog.live : WallpaperCatalog.online
    }

    /// "<source>-<id>.<ext>", the extension from the file (or the kind's own).
    public static func fileName(for item: OnlineBackground, fileURL: URL) -> String {
        let ext = fileURL.pathExtension.lowercased()
        let known = item.kind == .video ? WallpaperCatalog.videoExtensions : WallpaperCatalog.imageExtensions
        return "\(item.id).\(known.contains(ext) ? ext : (item.kind == .video ? "mp4" : "jpg"))"
    }

    public static func wallpaperID(for item: OnlineBackground) -> String {
        "\(folder(for: item.kind))/\(item.id)"
    }
}

/// Who made a downloaded background, and where it came from.
public struct BackgroundCredit: Codable, Equatable, Sendable {
    public let source: BackgroundSourceID
    public let title: String
    public let author: String?
    public let pageURL: URL
    public let width: Int
    public let height: Int

    public init(source: BackgroundSourceID, title: String, author: String?, pageURL: URL, width: Int, height: Int) {
        self.source = source
        self.title = title
        self.author = author
        self.pageURL = pageURL
        self.width = width
        self.height = height
    }

    /// "Wallhaven · uploaded by <name>", "Danbooru · art by <artist>".
    public var line: String {
        guard let author, !author.isEmpty else { return source.title }
        switch source {
        case .wallhaven: return "\(source.title) · uploaded by \(author)"
        case .danbooru: return "\(source.title) · art by \(author)"
        case .motionbgs, .steam: return "\(source.title) · \(author)"
        }
    }
}

/// `Wallpapers/credits.json`: wallpaper id → credit.
public enum BackgroundCredits {
    public static let fileName = "credits.json"

    public static func load(from file: URL) -> [String: BackgroundCredit] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: BackgroundCredit].self, from: data)) ?? [:]
    }

    public static func save(_ credits: [String: BackgroundCredit], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(credits).write(to: file, options: .atomic)
    }
}

// MARK: - Browsing

/// One source's grid on the background step: a chip row of categories above
/// tiles that page in as the focus nears their end.
public struct OnlineBrowseState: Equatable {
    public enum Focus: Equatable { case chips, tile(Int) }
    public static let columns = 3

    public let source: BackgroundSourceID
    public let categories: [BackgroundCategory]
    public var categoryIndex = 0 {
        didSet { if categoryIndex != oldValue { startOver() } }
    }
    public private(set) var query = ""
    public private(set) var items: [OnlineBackground] = []
    public private(set) var nextPage = 1
    public private(set) var hasMore = true
    public var focus: Focus = .chips

    public init(source: BackgroundSourceID) {
        self.source = source
        categories = source.categories
    }

    public var category: BackgroundCategory { categories[min(categoryIndex, categories.count - 1)] }

    public var focusedItem: OnlineBackground? {
        guard case .tile(let index) = focus, items.indices.contains(index) else { return nil }
        return items[index]
    }

    /// Whether the next page should load now: none yet, or the focus within two rows of the end.
    public var wantsMore: Bool {
        guard hasMore, !(category.isSearch && query.isEmpty) else { return false }
        guard case .tile(let index) = focus else { return items.isEmpty }
        return index >= items.count - 2 * Self.columns
    }

    /// Left/right on the chips changes the category; down enters the grid, up from its first row leaves it.
    @discardableResult
    public mutating func move(_ direction: GridDirection) -> Bool {
        switch focus {
        case .chips:
            switch direction {
            case .left where categoryIndex > 0: categoryIndex -= 1
            case .right where categoryIndex < categories.count - 1: categoryIndex += 1
            case .down where !items.isEmpty: focus = .tile(0)
            default: return false
            }
        case .tile(let index):
            if direction == .up, index < Self.columns {
                focus = .chips
            } else if let next = GridNavigation.move(index, direction, count: items.count, columns: Self.columns) {
                focus = .tile(next)
            } else {
                return false
            }
        }
        return true
    }

    public mutating func append(_ page: OnlinePage) {
        let known = Set(items.map(\.id))
        items += page.items.filter { !known.contains($0.id) }
        hasMore = page.hasMore
        nextPage += 1
    }

    /// New words for Search: the grid starts over.
    public mutating func search(_ words: String) {
        query = words.trimmingCharacters(in: .whitespacesAndNewlines)
        startOver()
    }

    private mutating func startOver() {
        items = []
        nextPage = 1
        hasMore = true
        focus = .chips
    }
}
