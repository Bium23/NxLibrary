import Foundation

/// When a store's title is the player's game: the same name, or the same name
/// with an edition after it ("Voidheart Edition", "Nintendo Switch Edition").
/// A sequel, a DLC or a soundtrack never is.
public enum ArtworkNames {
    /// Platform words a store adds to the name.
    private static let platformTails = [["nintendo", "switch", "edition"], ["for", "nintendo", "switch"],
                                        ["nintendo", "switch"]]

    public static func matches(_ title: String, _ names: [String]) -> Bool {
        let store = words(title)
        guard !store.isEmpty else { return false }
        return names.contains { name in
            let game = words(name)
            guard !game.isEmpty, store.starts(with: game) else { return false }
            let rest = store.dropFirst(game.count)
            return rest.isEmpty || (rest.last == "edition" && rest.count <= 5)
        }
    }

    private static func words(_ name: String) -> [String] {
        var list = GameTDB.normalize(name).split(separator: " ").map(String.init)
        for tail in platformTails where list.count > tail.count && list.suffix(tail.count).elementsEqual(tail) {
            list.removeLast(tail.count)
            break
        }
        return list
    }
}

/// Every online source the picker lists by itself, in its order: Steam, the other stores (Xbox, GOG, Nintendo Europe),
/// then the databases (TheGamesDB, Wikidata), then the wikis' logos and Wallhaven's backgrounds. LaunchBox and
/// SteamGridDB are browsed on their own from Change artwork (`ArtworkBrowseSource`).
public enum OnlineArtwork {
    /// Screenshots kept per source.
    static let screenshotLimit = 4

    /// Asks every source that has art for `slot` (all of them for nil) at once.
    public static func find(names: [String], slot: ArtworkSlot? = nil,
                            client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> [ArtworkCandidate] {
        func wants(_ slots: Set<ArtworkSlot>) -> Bool { slot.map(slots.contains) ?? true }
        async let wikidata = wants([.logo, .cover, .background]) ? WikidataArt.find(names: names, client: client)
                                                                  : WikidataArt.Found(logos: [], steamAppID: nil)
        async let steamSearch = wants([.logo, .cover, .background]) ? SteamStoreArt.findAppID(names: names, client: client)
                                                                     : nil
        async let xbox = wants([.cover, .background, .icon]) ? XboxStoreArt.find(names: names, client: client) : []
        async let gog = wants([.logo, .cover, .background]) ? GOGArt.find(names: names, client: client) : []
        async let europe = wants([.background, .icon]) ? NintendoEuropeArt.find(names: names, client: client) : []
        async let gamesDB = wants([.logo, .cover, .background]) ? TheGamesDBArt.find(names: names, client: client) : []
        async let commons = wants([.logo]) ? MediaWikiLogos.commons.candidates(names: names, client: client) : []
        async let wikis = wants([.logo]) ? fanWikiLogos(names: names, client: client) : []
        async let wallhaven = wants([.background]) ? WallhavenGameArt.find(names: names, client: client) : []

        let found = await wikidata
        var steam: [ArtworkCandidate] = []
        if let appID = await steamSearch ?? found.steamAppID {
            steam = ArtworkSlot.allCases.flatMap { SteamStoreArt.candidates(appID: appID, slot: $0) }
            if wants([.background]), let url = SteamStoreArt.screenshotsURL(appID: appID),
               let data = await OnlineArtworkRequest.data(url, client: client) {
                steam += SteamStoreArt.screenshots(in: data, appID: appID)
            }
        }
        let wikidataLogos = found.logos.map { ArtworkCandidate(slot: .logo, source: "Wikidata", url: $0) }
        let all = steam + (await xbox) + (await gog) + (await europe) + (await gamesDB) + wikidataLogos
            + (await commons) + (await wikis) + (await wallhaven)
        var seen: Set<URL> = []
        return all.filter { (slot == nil || $0.slot == slot) && seen.insert($0.url).inserted }
    }

    private static func fanWikiLogos(names: [String], client: ArtworkHTTPClient) async -> [ArtworkCandidate] {
        await withTaskGroup(of: (Int, [ArtworkCandidate]).self) { group in
            for (index, wiki) in MediaWikiLogos.fanWikis.enumerated() {
                group.addTask { (index, await wiki.candidates(names: names, client: client)) }
            }
            var results: [(Int, [ArtworkCandidate])] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }

    /// The first screenshots as numbered backgrounds.
    static func screenshots(_ links: [String], source: String, stripQuery: Bool = false) -> [ArtworkCandidate] {
        links.compactMap { link -> URL? in
            guard var components = URLComponents(string: link) else { return nil }
            if stripQuery { components.query = nil }
            return components.url
        }
        .prefix(screenshotLimit)
        .enumerated()
        .map { ArtworkCandidate(slot: .background, source: "\(source) \($0.offset + 1)", url: $0.element) }
    }
}

/// The Microsoft Store (Xbox): a poster cover, a clean hero background and the
/// titled one, screenshots, and a square box art for the icon.
public enum XboxStoreArt {
    public static func suggestURL(for name: String) -> URL? {
        let term = SteamStoreArt.plain(name)
        guard !term.isEmpty else { return nil }
        var components = URLComponents(string: "https://displaycatalog.mp.microsoft.com/v7.0/productFamilies/autosuggest")!
        components.queryItems = [.init(name: "market", value: "US"), .init(name: "languages", value: "en-US"),
                                 .init(name: "query", value: term), .init(name: "productFamilyNames", value: "Games")]
        return components.url
    }

    /// The game (never an add-on) named like one of `names`.
    public static func productID(in data: Data, matching names: [String]) -> String? {
        struct Wire: Decodable {
            struct Family: Decodable { var Products: [Product]? }
            struct Product: Decodable { var ProductId: String; var `Type`: String?; var Title: String }
            var Results: [Family]?
        }
        let products = (try? JSONDecoder().decode(Wire.self, from: data))?.Results?.flatMap { $0.Products ?? [] } ?? []
        return products.first { $0.Type == "Game" && ArtworkNames.matches($0.Title, names) }?.ProductId
    }

    public static func productURL(id: String) -> URL? {
        var components = URLComponents(string: "https://displaycatalog.mp.microsoft.com/v7.0/products")!
        components.queryItems = [.init(name: "bigIds", value: id), .init(name: "market", value: "US"),
                                 .init(name: "languages", value: "en-US")]
        return components.url
    }

    public static func candidates(in data: Data) -> [ArtworkCandidate] {
        struct Wire: Decodable {
            struct Product: Decodable { var LocalizedProperties: [Localized]? }
            struct Localized: Decodable { var Images: [Image]? }
            struct Image: Decodable { var ImagePurpose: String; var Uri: String }
            var Products: [Product]?
        }
        let images = (try? JSONDecoder().decode(Wire.self, from: data))?.Products?.first?
            .LocalizedProperties?.first?.Images ?? []
        func links(_ purpose: String) -> [String] {
            images.filter { $0.ImagePurpose == purpose }.map { $0.Uri.hasPrefix("//") ? "https:" + $0.Uri : $0.Uri }
        }
        func art(_ slot: ArtworkSlot, _ purpose: String, _ source: String) -> [ArtworkCandidate] {
            links(purpose).prefix(1).compactMap(URL.init(string:)).map { ArtworkCandidate(slot: slot, source: source, url: $0) }
        }
        return art(.cover, "Poster", "Xbox Store")
            + art(.background, "SuperHeroArt", "Xbox Store")
            + art(.background, "TitledHeroArt", "Xbox Store · titled")
            + OnlineArtwork.screenshots(links("Screenshot"), source: "Xbox Store screenshot")
            + art(.icon, "BoxArt", "Xbox Store")
    }

    public static func find(names: [String], client: ArtworkHTTPClient) async -> [ArtworkCandidate] {
        guard let name = names.first, let url = suggestURL(for: name),
              let data = await OnlineArtworkRequest.data(url, client: client),
              let id = productID(in: data, matching: names), let detail = productURL(id: id),
              let product = await OnlineArtworkRequest.data(detail, client: client) else { return [] }
        return candidates(in: product)
    }
}

/// GOG's catalog: the logo without a background, the vertical cover, the Galaxy
/// background, the wide cover and screenshots at full size.
public enum GOGArt {
    public static func searchURL(for name: String) -> URL? {
        let term = SteamStoreArt.plain(name)
        guard !term.isEmpty else { return nil }
        var components = URLComponents(string: "https://catalog.gog.com/v1/catalog")!
        components.queryItems = [.init(name: "query", value: "like:\(term)"), .init(name: "limit", value: "10"),
                                 .init(name: "productType", value: "in:game")]
        return components.url
    }

    public static func candidates(in data: Data, matching names: [String]) -> [ArtworkCandidate] {
        struct Wire: Decodable {
            struct Product: Decodable {
                var title: String
                var logo: String?
                var coverVertical: String?
                var coverHorizontal: String?
                var galaxyBackgroundImage: String?
                var screenshots: [String]?
            }
            var products: [Product]?
        }
        guard let product = (try? JSONDecoder().decode(Wire.self, from: data))?.products?
            .first(where: { ArtworkNames.matches($0.title, names) }) else { return [] }
        func art(_ slot: ArtworkSlot, _ link: String?) -> [ArtworkCandidate] {
            link.flatMap(URL.init(string:)).map { [ArtworkCandidate(slot: slot, source: "GOG", url: $0)] } ?? []
        }
        // A screenshot without its size template is the original.
        let shots = (product.screenshots ?? []).map { $0.replacingOccurrences(of: "_{formatter}", with: "") }
        return art(.logo, product.logo) + art(.cover, product.coverVertical)
            + art(.background, product.galaxyBackgroundImage) + art(.background, product.coverHorizontal)
            + OnlineArtwork.screenshots(shots, source: "GOG screenshot")
    }

    public static func find(names: [String], client: ArtworkHTTPClient) async -> [ArtworkCandidate] {
        guard let name = names.first, let url = searchURL(for: name),
              let data = await OnlineArtworkRequest.data(url, client: client) else { return [] }
        return candidates(in: data, matching: names)
    }
}

/// Nintendo of Europe's store search: the wide banner (asked at 1600 px wide) and
/// the square image.
public enum NintendoEuropeArt {
    public static func searchURL(for name: String) -> URL? {
        let term = SteamStoreArt.plain(name)
        guard !term.isEmpty else { return nil }
        var components = URLComponents(string: "https://searching.nintendo-europe.com/en/select")!
        components.queryItems = [
            .init(name: "q", value: term), .init(name: "fq", value: "type:GAME AND system_type:nintendoswitch*"),
            .init(name: "rows", value: "10"), .init(name: "wt", value: "json"),
            .init(name: "fl", value: "title,image_url_h16x9_s,image_url_h2x1_s,image_url_sq_s")
        ]
        return components.url
    }

    public static func candidates(in data: Data, matching names: [String]) -> [ArtworkCandidate] {
        struct Wire: Decodable {
            struct Response: Decodable { var docs: [Doc]? }
            struct Doc: Decodable {
                var title: String
                var image_url_h16x9_s: String?
                var image_url_h2x1_s: String?
                var image_url_sq_s: String?
            }
            var response: Response?
        }
        guard let doc = (try? JSONDecoder().decode(Wire.self, from: data))?.response?.docs?
            .first(where: { ArtworkNames.matches($0.title, names) }) else { return [] }
        var list: [ArtworkCandidate] = []
        if let link = doc.image_url_h16x9_s ?? doc.image_url_h2x1_s, let small = URL(string: link) {
            let large = URL(string: link.replacingOccurrences(of: "image500w", with: "image1600w"))
            list.append(ArtworkCandidate(slot: .background, source: "Nintendo Europe", url: large ?? small,
                                         fallback: large == small ? nil : small))
        }
        if let link = doc.image_url_sq_s, let url = URL(string: link) {
            list.append(ArtworkCandidate(slot: .icon, source: "Nintendo Europe", url: url))
        }
        return list
    }

    public static func find(names: [String], client: ArtworkHTTPClient) async -> [ArtworkCandidate] {
        guard let name = names.first, let url = searchURL(for: name),
              let data = await OnlineArtworkRequest.data(url, client: client) else { return [] }
        return candidates(in: data, matching: names)
    }
}

/// Wikidata's entry for the video game: its logo file on Commons and its Steam app,
/// which finds Steam's art when the names differ.
public enum WikidataArt {
    public struct Found: Equatable, Sendable {
        public var logos: [URL]
        public var steamAppID: Int?
    }

    public static func searchURL(for name: String) -> URL? {
        let term = SteamStoreArt.plain(name)
        guard !term.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = [.init(name: "action", value: "wbsearchentities"), .init(name: "search", value: term),
                                 .init(name: "language", value: "en"), .init(name: "type", value: "item"),
                                 .init(name: "limit", value: "5"), .init(name: "format", value: "json")]
        return components.url
    }

    /// Items labelled like the game, in search order.
    public static func ids(in data: Data, matching names: [String]) -> [String] {
        struct Wire: Decodable { struct Item: Decodable { var id: String; var label: String? }; var search: [Item]? }
        let items = (try? JSONDecoder().decode(Wire.self, from: data))?.search ?? []
        return items.filter { ArtworkNames.matches($0.label ?? "", names) }.map(\.id)
    }

    public static func entitiesURL(ids: [String]) -> URL? {
        guard !ids.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = [.init(name: "action", value: "wbgetentities"),
                                 .init(name: "ids", value: ids.joined(separator: "|")),
                                 .init(name: "props", value: "claims"), .init(name: "format", value: "json")]
        return components.url
    }

    /// The first item that is a video game (Q7889): its logos (P154), never a black one,
    /// and its Steam app (P1733).
    public static func parse(_ data: Data, order: [String]) -> Found {
        struct Wire: Decodable {
            struct Entity: Decodable { var claims: [String: [Claim]]? }
            struct Claim: Decodable { var mainsnak: Snak }
            struct Snak: Decodable { var datavalue: Value? }
            struct Value: Decodable { var value: Content }
            enum Content: Decodable {
                case text(String), item(String), other
                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let text = try? container.decode(String.self) { self = .text(text); return }
                    struct Item: Decodable { var id: String }
                    if let item = try? container.decode(Item.self) { self = .item(item.id); return }
                    self = .other
                }
            }
            var entities: [String: Entity]?
        }
        let entities = (try? JSONDecoder().decode(Wire.self, from: data))?.entities ?? [:]
        for id in order {
            guard let claims = entities[id]?.claims else { continue }
            func values(_ property: String) -> [Wire.Content] { (claims[property] ?? []).compactMap { $0.mainsnak.datavalue?.value } }
            guard values("P31").contains(where: { if case .item("Q7889") = $0 { return true } else { return false } }) else {
                continue
            }
            let logos = values("P154").compactMap { value -> URL? in
                guard case .text(let file) = value, !file.lowercased().contains("black") else { return nil }
                var components = URLComponents(string: "https://commons.wikimedia.org/wiki/Special:FilePath/")!
                components.path += file.replacingOccurrences(of: " ", with: "_")
                components.queryItems = [.init(name: "width", value: String(MediaWikiLogos.renderWidth))]
                return components.url
            }
            let steam = values("P1733").lazy.compactMap { value -> Int? in
                if case .text(let text) = value { return Int(text) } else { return nil }
            }.first
            return Found(logos: logos, steamAppID: steam)
        }
        return Found(logos: [], steamAppID: nil)
    }

    public static func find(names: [String], client: ArtworkHTTPClient) async -> Found {
        let none = Found(logos: [], steamAppID: nil)
        guard let name = names.first, let url = searchURL(for: name),
              let data = await OnlineArtworkRequest.data(url, client: client) else { return none }
        let ids = ids(in: data, matching: names)
        guard let detail = entitiesURL(ids: ids),
              let entities = await OnlineArtworkRequest.data(detail, client: client) else { return none }
        return parse(entities, order: ids)
    }
}

/// TheGamesDB, the community database: clear logos, box fronts, fan art and
/// screenshots for Switch games, read from its public pages.
public enum TheGamesDBArt {
    static let switchPlatform = "4971"

    public static func searchURL(for name: String) -> URL? {
        let term = SteamStoreArt.plain(name)
        guard !term.isEmpty else { return nil }
        var components = URLComponents(string: "https://thegamesdb.net/search.php")!
        components.queryItems = [.init(name: "name", value: term), .init(name: "platform_id[]", value: switchPlatform)]
        return components.url
    }

    /// The first result card whose title is the game's.
    public static func gameID(in html: String, matching names: [String]) -> Int? {
        for card in html.components(separatedBy: "game.php?id=").dropFirst() {
            let id = Int(card.prefix { $0.isNumber })
            guard let id, let footer = card.range(of: "card-footer"),
                  let open = card.range(of: "<p>", range: footer.upperBound..<card.endIndex),
                  let close = card.range(of: "</p>", range: open.upperBound..<card.endIndex) else { continue }
            let title = decodeEntities(String(card[open.upperBound..<close.lowerBound]))
            if ArtworkNames.matches(title, names) { return id }
        }
        return nil
    }

    public static func gameURL(id: Int) -> URL {
        URL(string: "https://thegamesdb.net/game.php?id=\(id)")!
    }

    public static func candidates(in html: String, id: Int) -> [ArtworkCandidate] {
        let pattern = #"https://cdn\.thegamesdb\.net/images/original/(clearlogo|boxart/front|fanart|screenshot)/\#(id)-\d+\.(png|jpg)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var seen: Set<String> = []
        var byKind: [String: [String]] = [:]
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let whole = Range(match.range, in: html), let kind = Range(match.range(at: 1), in: html) else { continue }
            let link = String(html[whole])
            if seen.insert(link).inserted { byKind[String(html[kind]), default: []].append(link) }
        }
        func art(_ slot: ArtworkSlot, _ kind: String, _ source: String) -> [ArtworkCandidate] {
            (byKind[kind] ?? []).compactMap(URL.init(string:)).map { ArtworkCandidate(slot: slot, source: source, url: $0) }
        }
        return art(.logo, "clearlogo", "TheGamesDB") + art(.cover, "boxart/front", "TheGamesDB")
            + art(.background, "fanart", "TheGamesDB fan art")
            + OnlineArtwork.screenshots(byKind["screenshot"] ?? [], source: "TheGamesDB screenshot")
    }

    public static func find(names: [String], client: ArtworkHTTPClient) async -> [ArtworkCandidate] {
        guard let name = names.first, let url = searchURL(for: name),
              let data = await OnlineArtworkRequest.data(url, client: client),
              let id = gameID(in: String(decoding: data, as: UTF8.self), matching: names),
              let page = await OnlineArtworkRequest.data(gameURL(id: id), client: client) else { return [] }
        return candidates(in: String(decoding: page, as: UTF8.self), id: id)
    }

    private static func decodeEntities(_ text: String) -> String {
        [("&amp;", "&"), ("&#039;", "'"), ("&#39;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">")]
            .reduce(text.trimmingCharacters(in: .whitespacesAndNewlines)) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}

/// Wallhaven's wallpapers tagged with the game's name, as backgrounds.
public enum WallhavenGameArt {
    static let limit = 4

    public static func searchURL(for name: String) -> URL? {
        let search = WallhavenAPI.categories.first { $0.isSearch }!
        return WallhavenAPI.searchURL(search, query: SteamStoreArt.plain(name), page: 1)
    }

    public static func candidates(in data: Data) -> [ArtworkCandidate] {
        let items = (try? WallhavenAPI.parseSearch(data))?.items ?? []
        return items.compactMap(\.fileURL).prefix(limit)
            .map { ArtworkCandidate(slot: .background, source: "Wallhaven", url: $0) }
    }

    public static func find(names: [String], client: ArtworkHTTPClient) async -> [ArtworkCandidate] {
        guard let name = names.first, let url = searchURL(for: name),
              let data = await OnlineArtworkRequest.data(url, client: client) else { return [] }
        return candidates(in: data)
    }
}
