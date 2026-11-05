import Foundation

/// The LaunchBox Games Database (https://gamesdb.launchbox-app.com), read from its public pages when the player
/// browses it from Change artwork or opens a game's Details without screenshots: the game's search result, then the
/// images its page lists. LaunchBox has no API; a page is read the way TheGamesDB's are, one search and one game page
/// per lookup, and a page that changes simply finds nothing.
///
/// The images come from the page's Nuxt payload (`__NUXT_DATA__`), which names each image's kind, region, small
/// preview and full file with its size. The grid shows the preview; the full file is downloaded only when chosen.
public enum LaunchBoxArt {
    public static let site = URL(string: "https://gamesdb.launchbox-app.com")!
    static let images = URL(string: "https://images.launchbox-app.com/")!
    static let gameplay = "Screenshot - Gameplay"
    /// Screenshots Details shows when Title DB has none.
    public static let screenshotLimit = 6

    /// The kinds of image offered, and the slot each fills, in the order a slot lists them.
    static let order = ["Box - Front", "Box - Front - Reconstructed", "Clear Logo", "Fanart - Background", gameplay, "Square"]
    static let kinds: [String: ArtworkSlot] = [
        "Box - Front - Reconstructed": .cover,
        "Box - Front": .cover,
        "Clear Logo": .logo,
        "Fanart - Background": .background,
        gameplay: .background,
        "Square": .icon,
    ]

    public static func searchURL(for name: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let term = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, let path = term.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "/games/results/\(path)", relativeTo: site)?.absoluteURL
    }

    public struct Result: Equatable {
        public let path: String
        public let title: String
        public let platform: String
    }

    /// The search page's game cards: link, title and platform.
    public static func results(in html: String) -> [Result] {
        html.components(separatedBy: "href=\"/games/details/").dropFirst().compactMap { card in
            guard let slug = card.split(separator: "\"", maxSplits: 1).first,
                  slug.range(of: #"^\d+-[A-Za-z0-9-]*$"#, options: .regularExpression) != nil,
                  let title = capture(#"<h3[^>]*>([^<]+)</h3>"#, in: card),
                  let platform = capture(#"</h3>\s*<p[^>]*>([^<]+)</p>"#, in: card) else { return nil }
            return Result(path: "/games/details/\(slug)", title: unescape(title).trimmingCharacters(in: .whitespaces),
                          platform: unescape(platform).trimmingCharacters(in: .whitespaces))
        }
    }

    /// The result that is this game on a Switch: its own console first (Switch 2 for a title ID starting 04).
    /// `loose` (a name the player typed) falls back to the first Switch result when no title matches the name.
    public static func pick(_ results: [Result], names: [String], switch2: Bool, loose: Bool = false) -> Result? {
        let own = switch2 ? "Nintendo Switch 2" : "Nintendo Switch"
        let named = results.filter { ArtworkNames.matches($0.title, names) }
        if let found = named.first(where: { $0.platform == own }) ?? named.first(where: { $0.platform.hasPrefix("Nintendo Switch") }) {
            return found
        }
        guard loose else { return nil }
        return results.first { $0.platform == own } ?? results.first { $0.platform.hasPrefix("Nintendo Switch") }
    }

    /// The images a game page's payload lists, each in its slot with its preview, full file and size, credited
    /// "LaunchBox · Box - Front (Europe)". Kinds not offered (backs, spines…) are left out.
    public static func candidates(in html: String) -> [ArtworkCandidate] {
        var list: [ArtworkCandidate] = []
        var seen = Set<String>()
        let listed = payloadImages(in: html).enumerated().sorted {
            (order.firstIndex(of: $0.element.kind) ?? order.count, $0.offset) < (order.firstIndex(of: $1.element.kind) ?? order.count, $1.offset)
        }.map(\.element)
        for image in listed {
            guard let slot = kinds[image.kind], seen.insert(image.full).inserted,
                  let preview = URL(string: image.preview, relativeTo: images)?.absoluteURL,
                  let full = URL(string: image.full, relativeTo: images)?.absoluteURL else { continue }
            let region = image.region.map { " (\($0))" } ?? ""
            list.append(ArtworkCandidate(slot: slot, source: "LaunchBox · \(image.kind)\(region)", url: preview,
                                         full: full, width: image.width, height: image.height))
        }
        return list
    }

    struct PayloadImage: Equatable {
        let kind: String
        let region: String?
        let preview: String
        let full: String
        let width: Int?
        let height: Int?
    }

    /// Nuxt writes its payload as one flat JSON array in which an object's values are the indices of other entries.
    static func payloadImages(in html: String) -> [PayloadImage] {
        guard let start = html.range(of: "id=\"__NUXT_DATA__\""),
              let open = html.range(of: ">", range: start.upperBound..<html.endIndex),
              let close = html.range(of: "</script>", range: open.upperBound..<html.endIndex),
              let array = try? JSONSerialization.jsonObject(with: Data(html[open.upperBound..<close.lowerBound].utf8)) as? [Any]
        else { return [] }
        func value(_ object: [String: Any], _ key: String) -> Any? {
            guard let index = object[key] as? Int, array.indices.contains(index) else { return nil }
            return array[index]
        }
        func text(_ object: [String: Any], _ key: String) -> String? {
            (value(object, key) as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        func number(_ object: [String: Any], _ key: String) -> Int? {
            (value(object, key) as? NSNumber).map(\.intValue).flatMap { $0 > 0 ? $0 : nil }
        }
        return array.compactMap { entry in
            guard let object = entry as? [String: Any], let kind = text(object, "imageTypeName"),
                  let preview = text(object, "imageFileName"), let full = text(object, "fullGameImageFileName"),
                  safeName(preview), safeName(full) else { return nil }
            return PayloadImage(kind: kind, region: text(object, "regionName"), preview: preview, full: full,
                                width: number(object, "fullGameImageWidth"), height: number(object, "fullGameImageHeight"))
        }
    }

    /// A file name on LaunchBox's image host, never a path or another site.
    private static func safeName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp)$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A game LaunchBox lists: its page and its images.
    public struct Game: Equatable, Sendable {
        public let page: URL
        public let candidates: [ArtworkCandidate]
    }

    /// Searches each name until one finds this game on a Switch, then reads its page.
    public static func game(names: [String], switch2: Bool, loose: Bool = false,
                            client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> Game? {
        for name in names {
            guard let url = searchURL(for: name), let data = await OnlineArtworkRequest.data(url, client: client),
                  let html = String(data: data, encoding: .utf8),
                  let result = pick(results(in: html), names: names, switch2: switch2, loose: loose),
                  let page = URL(string: result.path, relativeTo: site)?.absoluteURL else { continue }
            guard let body = await OnlineArtworkRequest.data(page, client: client),
                  let text = String(data: body, encoding: .utf8) else { return nil }
            return Game(page: page, candidates: candidates(in: text))
        }
        return nil
    }

    /// The game's gameplay screenshots at full size, for Details when Title DB has none.
    public static func screenshots(names: [String], switch2: Bool,
                                   client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> [URL]? {
        guard let game = await game(names: names, switch2: switch2, client: client) else { return nil }
        return Array(game.candidates.filter { $0.source.hasPrefix("LaunchBox · \(gameplay)") }
            .compactMap(\.full).prefix(screenshotLimit))
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func unescape(_ text: String) -> String {
        var out = text
        for (entity, value) in [("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: value)
        }
        return out
    }
}
