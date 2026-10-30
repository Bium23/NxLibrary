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

    /// The app whose normalised name equals one of `names`'; a DLC or a soundtrack never does.
    public static func appID(in data: Data, matching names: [String]) -> Int? {
        struct Wire: Decodable {
            struct Item: Decodable { var type: String?; var name: String; var id: Int }
            var items: [Item]?
        }
        guard let items = (try? JSONDecoder().decode(Wire.self, from: data))?.items else { return nil }
        let keys = Set(names.map(GameTDB.normalize).filter { !$0.isEmpty })
        return items.first { ($0.type ?? "app") == "app" && keys.contains(GameTDB.normalize($0.name)) }?.id
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

    static func url(_ appID: Int, _ file: String) -> URL {
        URL(string: "\(assets)/\(appID)/\(file)")!
    }

    static func plain(_ name: String) -> String {
        var text = name
        for mark in ["™", "®", "©"] { text = text.replacingOccurrences(of: mark, with: "") }
        return text.split(separator: " ").joined(separator: " ")
    }
}

/// Game logos on Wikimedia Commons: free files, often the official wordmark
/// without a background. Kept only when the file is named after the game, then
/// nothing or a logo word.
public enum CommonsLogos {
    /// Longest side asked of Commons' renderer; it rounds up to its own sizes.
    static let renderWidth = 1600

    public static func searchURL(for name: String) -> URL? {
        let term = SteamStoreArt.plain(name)
        guard !term.isEmpty else { return nil }
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"), .init(name: "generator", value: "search"),
            .init(name: "gsrnamespace", value: "6"), .init(name: "gsrsearch", value: "\(term) logo"),
            .init(name: "gsrlimit", value: "12"), .init(name: "prop", value: "imageinfo"),
            .init(name: "iiprop", value: "url|size|mime"), .init(name: "iiurlwidth", value: String(renderWidth))
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

    public static func find(names: [String], client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> [URL] {
        guard let name = names.first, let url = searchURL(for: name),
              let data = await OnlineArtworkRequest.data(url, client: client) else { return [] }
        return parse(data, gameNames: names)
    }

    private static let logoWords: Set<String> = ["logo", "textlogo", "wordmark", "logotype"]
    /// Words that may follow the name before the logo word ("text-only logo", "video game logo");
    /// anything else ("Silksong logo") is another game.
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
