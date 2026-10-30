import Foundation

/// Steam's own art for a game that is also on Steam: the publisher's logo with a
/// transparent background, the library cover and the library background. Found by
/// the store's public search, and only for a game whose name is the same.
public enum SteamStoreArt {
    static let assets = "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps"

    /// The store search for `name`, without trademark signs.
    public static func searchURL(for name: String) -> URL? {
        let term = plain(name)
        guard !term.isEmpty else { return nil }
        var components = URLComponents(string: "https://store.steampowered.com/api/storesearch/")!
        components.queryItems = [.init(name: "term", value: term), .init(name: "l", value: "english"),
                                 .init(name: "cc", value: "US")]
        return components.url
    }

    /// The app named like one of `names` (`ArtworkNames`); a DLC or a soundtrack never is.
    public static func appID(in data: Data, matching names: [String]) -> Int? {
        struct Wire: Decodable {
            struct Item: Decodable { var type: String?; var name: String; var id: Int }
            var items: [Item]?
        }
        guard let items = (try? JSONDecoder().decode(Wire.self, from: data))?.items else { return nil }
        return items.first { ($0.type ?? "app") == "app" && ArtworkNames.matches($0.name, names) }?.id
    }

    /// Searches each distinct name in turn until one matches.
    public static func findAppID(names: [String], client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> Int? {
        var searched: Set<String> = []
        for name in names {
            let key = GameTDB.normalize(name)
            guard !key.isEmpty, searched.insert(key).inserted, let url = searchURL(for: name) else { continue }
            guard let data = await OnlineArtworkRequest.data(url, client: client) else { continue }
            if let id = appID(in: data, matching: names) { return id }
        }
        return nil
    }

    /// Twice the size where Steam has it, its standard size otherwise.
    public static func candidates(appID: Int, slot: ArtworkSlot) -> [ArtworkCandidate] {
        let file: (String, String)
        switch slot {
        case .logo: file = ("logo_2x.png", "logo.png")
        case .cover: file = ("library_600x900_2x.jpg", "library_600x900.jpg")
        case .background: file = ("library_hero_2x.jpg", "library_hero.jpg")
        case .icon: return []
        }
        return [ArtworkCandidate(slot: slot, source: "Steam", url: url(appID, file.0), fallback: url(appID, file.1))]
    }

    public static func screenshotsURL(appID: Int) -> URL? {
        var components = URLComponents(string: "https://store.steampowered.com/api/appdetails")!
        components.queryItems = [.init(name: "appids", value: String(appID)), .init(name: "filters", value: "screenshots")]
        return components.url
    }

    /// The store page's first screenshots at full size, as backgrounds.
    public static func screenshots(in data: Data, appID: Int) -> [ArtworkCandidate] {
        struct Shot: Decodable { var path_full: String }
        struct Body: Decodable { struct Inner: Decodable { var screenshots: [Shot]? }; var data: Inner? }
        guard let body = (try? JSONDecoder().decode([String: Body].self, from: data))?[String(appID)],
              let shots = body.data?.screenshots else { return [] }
        return OnlineArtwork.screenshots(shots.map(\.path_full), source: "Steam screenshot", stripQuery: true)
    }

    static func url(_ appID: Int, _ file: String) -> URL {
        URL(string: "\(assets)/\(appID)/\(file)")!
    }

    static func plain(_ name: String) -> String {
        var text = name
        for mark in ["™", "®", "©"] { text = text.replacingOccurrences(of: mark, with: "") }
        return text.split(separator: " ").joined(separator: " ")
    }
}

/// Game logos in a MediaWiki's files: Wikimedia Commons (free files, often the
/// official wordmark) and Nintendo fan wikis. Kept only when the file is a PNG or
/// SVG named after the game, then nothing or a logo word.
public struct MediaWikiLogos: Sendable {
    public let source: String
    public let endpoint: URL

    public static let commons = MediaWikiLogos(source: "Wikimedia Commons",
                                               endpoint: URL(string: "https://commons.wikimedia.org/w/api.php")!)
    /// Nintendo series wikis (NIWA) whose files are named after the games.
    public static let fanWikis: [MediaWikiLogos] = [
        ("Super Mario Wiki", "https://www.mariowiki.com/api.php"),
        ("SmashWiki", "https://www.ssbwiki.com/api.php"),
        ("Pikipedia", "https://www.pikminwiki.com/api.php"),
        ("Xeno Series Wiki", "https://www.xenoserieswiki.org/w/api.php"),
        ("WiKirby", "https://wikirby.com/w/api.php"),
        ("Metroid Wiki", "https://www.metroidwiki.org/w/api.php"),
        ("Fire Emblem Wiki", "https://fireemblemwiki.org/w/api.php"),
        ("Nookipedia", "https://nookipedia.com/w/api.php"),
    ].map { MediaWikiLogos(source: $0.0, endpoint: URL(string: $0.1)!) }

    /// Longest side asked of the wiki's renderer; Commons rounds up to its own sizes.
    static let renderWidth = 1600

    public func searchURL(for name: String) -> URL? {
        let term = SteamStoreArt.plain(name)
        guard !term.isEmpty else { return nil }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"), .init(name: "generator", value: "search"),
            .init(name: "gsrnamespace", value: "6"), .init(name: "gsrsearch", value: "\(term) logo"),
            .init(name: "gsrlimit", value: "12"), .init(name: "prop", value: "imageinfo"),
            .init(name: "iiprop", value: "url|size|mime"), .init(name: "iiurlwidth", value: String(Self.renderWidth))
        ]
        return components.url
    }

    /// PNG or SVG files of this game's logo, in search order. SVGs come rendered as PNG;
    /// a PNG larger than the render width comes scaled.
    public static func parse(_ data: Data, gameNames: [String]) -> [URL] {
        struct Wire: Decodable {
            struct Query: Decodable { var pages: [Page]? }
            struct Page: Decodable { var title: String; var index: Int?; var imageinfo: [Info]? }
            struct Info: Decodable { var mime: String; var width: Int; var url: String; var thumburl: String? }
            var query: Query?
        }
        guard let pages = (try? JSONDecoder().decode(Wire.self, from: data))?.query?.pages else { return [] }
        let keys = gameNames.map(GameTDB.normalize).filter { !$0.isEmpty }
        var urls: [URL] = []
        for page in pages.sorted(by: { ($0.index ?? 0) < ($1.index ?? 0) }) {
            guard let info = page.imageinfo?.first, ["image/png", "image/svg+xml"].contains(info.mime),
                  isLogo(title: page.title, keys: keys) else { continue }
            let link = info.mime == "image/png" && info.width <= renderWidth ? info.url : (info.thumburl ?? info.url)
            guard var components = URLComponents(string: link) else { continue }
            components.query = nil
            if let url = components.url, !urls.contains(url) { urls.append(url) }
        }
        return urls
    }

    public func find(names: [String], client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> [URL] {
        guard let name = names.first, let url = searchURL(for: name),
              let data = await OnlineArtworkRequest.data(url, client: client) else { return [] }
        return Self.parse(data, gameNames: names)
    }

    public func candidates(names: [String], client: ArtworkHTTPClient) async -> [ArtworkCandidate] {
        await find(names: names, client: client).map { ArtworkCandidate(slot: .logo, source: source, url: $0) }
    }

    private static let logoWords: Set<String> = ["logo", "textlogo", "wordmark", "logotype"]
    /// Words that may follow the name before the logo word ("text-only logo", "video game logo");
    /// anything else ("Silksong logo", "Japanese logo") is another game or another language.
    private static let leadWords = logoWords.union(["text", "only", "video", "game", "official", "english"])

    private static func isLogo(title: String, keys: [String]) -> Bool {
        var name = title.hasPrefix("File:") ? String(title.dropFirst(5)) : title
        if let dot = name.lastIndex(of: ".") { name = String(name[..<dot]) }
        let words = GameTDB.normalize(name).split(separator: " ").map(String.init)
        return keys.contains { key in
            let game = key.split(separator: " ").map(String.init)
            guard words.starts(with: game) else { return false }
            let rest = words.dropFirst(game.count)
            guard let first = rest.first else { return true }
            // Black lettering vanishes on the dark home.
            return leadWords.contains(first) && rest.contains(where: logoWords.contains) && !rest.contains("black")
        }
    }
}

/// Wikimedia Commons' logos, the first of the MediaWikis.
public enum CommonsLogos {
    public static func searchURL(for name: String) -> URL? { MediaWikiLogos.commons.searchURL(for: name) }
    public static func parse(_ data: Data, gameNames: [String]) -> [URL] { MediaWikiLogos.parse(data, gameNames: gameNames) }
    public static func find(names: [String], client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> [URL] {
        await MediaWikiLogos.commons.find(names: names, client: client)
    }
}

enum OnlineArtworkRequest {
    static func data(_ url: URL, client: ArtworkHTTPClient) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("NXLibrary/0.1 (macOS; personal app)", forHTTPHeaderField: "User-Agent")
        guard let (data, http) = try? await client.data(for: request), (200..<300).contains(http.statusCode) else {
            return nil
        }
        return data
    }
}
