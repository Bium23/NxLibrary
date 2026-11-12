import Foundation

public struct NintendoStoreMetadata: Codable, Equatable {
    public var titleId: String
    public var name: String
    public var description: String
    public var developers: [String]
    public var publishers: [String]
    public var genres: [String]
    public var releaseDate: String?
    public var storeURL: URL
    public var imageURL: URL?
    public var headerImageURL: URL?
    public var logoURL: URL?
    public var nsuid: String?
    public var fetchedAt: Date
    public var screenshotURLs: [URL] = []
    /// Where `screenshotURLs` came from when not the store or Title DB ("LaunchBox"); shown, never saved.
    public var screenshotSource: String?
    public var descriptionLanguage = "en"
    public var localeKey: String? = nil
    /// The last successful response for the requested description language, including an empty translation.
    public var descriptionCheckedAt: Date?

    public init(titleId: String, name: String, description: String, developers: [String],
                publishers: [String], genres: [String], releaseDate: String?, storeURL: URL,
                imageURL: URL?, headerImageURL: URL?, logoURL: URL? = nil,
                nsuid: String?, fetchedAt: Date, screenshotURLs: [URL] = []) {
        self.titleId = titleId
        self.name = name
        self.description = description
        self.developers = developers
        self.publishers = publishers
        self.genres = genres
        self.releaseDate = releaseDate
        self.storeURL = storeURL
        self.imageURL = imageURL
        self.headerImageURL = headerImageURL
        self.logoURL = logoURL
        self.nsuid = nsuid
        self.fetchedAt = fetchedAt
        self.screenshotURLs = screenshotURLs
    }

    private enum CodingKeys: String, CodingKey {
        case titleId, name, description, developers, publishers, genres, releaseDate
        case descriptionLanguage, localeKey, descriptionCheckedAt
        case storeURL, imageURL, headerImageURL, logoURL, nsuid, fetchedAt, screenshotURLs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        descriptionLanguage = try c.decodeIfPresent(String.self, forKey: .descriptionLanguage) ?? "en"
        localeKey = try c.decodeIfPresent(String.self, forKey: .localeKey)
        descriptionCheckedAt = try c.decodeIfPresent(Date.self, forKey: .descriptionCheckedAt)
        titleId = try c.decode(String.self, forKey: .titleId)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        developers = try c.decode([String].self, forKey: .developers)
        publishers = try c.decode([String].self, forKey: .publishers)
        genres = try c.decode([String].self, forKey: .genres)
        releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate)
        storeURL = try c.decode(URL.self, forKey: .storeURL)
        imageURL = try c.decodeIfPresent(URL.self, forKey: .imageURL)
        headerImageURL = try c.decodeIfPresent(URL.self, forKey: .headerImageURL)
        logoURL = try c.decodeIfPresent(URL.self, forKey: .logoURL)
        nsuid = try c.decodeIfPresent(String.self, forKey: .nsuid)
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
        screenshotURLs = try c.decodeIfPresent([URL].self, forKey: .screenshotURLs) ?? []
    }

    public var releaseYear: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        let year = String(releaseDate.prefix(4))
        return Int(year) == nil ? nil : year
    }
}

public enum NintendoStoreError: Error, Equatable, LocalizedError {
    case notFound
    case invalidURL
    case http(Int)
    case decoding

    public var errorDescription: String? {
        switch self {
        case .notFound: return L10n.text("No Nintendo Store entry was found for this game.")
        case .invalidURL: return L10n.text("The Nintendo Store URL is invalid.")
        case .http(let status): return L10n.format("Nintendo Store returned status %@.", [String(describing: (status))])
        case .decoding: return L10n.text("Nintendo Store returned a response this app could not read.")
        }
    }
}

public protocol NintendoStoreHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionNintendoStoreClient: NintendoStoreHTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// Reads the public Nintendo Store catalog used by nintendo.com. The keys are
/// the public Algolia search credentials embedded in Nintendo's own web client.
/// Data is cached for seven days; nothing is fetched while a game launches.
public final class NintendoStoreMetadataService: @unchecked Sendable {
    private static let appID = "U3B6GR4UA3"
    private static let newIndex = "store_all_products_en_us"
    private static let oldIndex = "ncom_game_en_us"
    private static let newKey = "a29c6927638bfd8cee23993e51e721c9"
    private static let oldKey = "6efbfb0f8f80defc44895018caf77504"
    private static let ttl: TimeInterval = 7 * 24 * 60 * 60

    private let client: NintendoStoreHTTPClient
    private let cacheDirectory: URL
    private let fileManager: FileManager
    private let refreshLock = NSLock()
    private var screenshotRefreshTried: Set<String> = []
    private var descriptionRetryAfter: [String: Date] = [:]

    public init(
        client: NintendoStoreHTTPClient = URLSessionNintendoStoreClient(),
        cacheDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NXLibrary/metadata"),
        fileManager: FileManager = .default
    ) {
        self.client = client
        self.cacheDirectory = cacheDirectory
        self.fileManager = fileManager
    }

    public func cached(for titleId: String, locale: AppLocale = AppLocale(language: .english, region: "US")) -> NintendoStoreMetadata? {
        func read(_ url: URL) -> NintendoStoreMetadata? {
            guard let data = try? Data(contentsOf: url),
                  let metadata = try? JSONDecoder().decode(NintendoStoreMetadata.self, from: data),
                  metadata.titleId == titleId else { return nil }
            return metadata
        }
        if let exact = read(cacheURL(for: titleId, locale: locale)) { return exact }
        // The provider localizes descriptions by language, not by formatting region.
        var alternatives: [NintendoStoreMetadata] = []
        if locale.language == .english,
           let legacy = read(cacheURL(for: titleId, locale: AppLocale(language: .english, region: "US"))) {
            alternatives.append(legacy)
        }
        let root = cacheDirectory.appendingPathComponent("localized")
        for folder in (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            where folder.lastPathComponent.hasPrefix(locale.language.rawValue + "_") {
            if let entry = read(folder.appendingPathComponent(Self.safeFileName(titleId) + ".json")) { alternatives.append(entry) }
        }
        return alternatives.max { $0.fetchedAt < $1.fetchedAt }
    }

    /// Whether `metadata` can be used without asking the network again: younger
    /// than the TTL, and not an entry cached before titledb screenshots existed.
    /// A titledb-style title (16 characters, "0100" prefix) with no screenshots
    /// is re-fetched once per app session (per service instance); offline, that
    /// one attempt fails and the cached entry is used for the rest of the session.
    public func isFresh(_ metadata: NintendoStoreMetadata, now: Date = Date(), locale: AppLocale = AppLocale(language: .english, region: "US")) -> Bool {
        guard (metadata.localeKey ?? "en_US").hasPrefix(locale.language.rawValue + "_") else { return false }
        guard now.timeIntervalSince(metadata.fetchedAt) < Self.ttl else { return false }
        if locale.metadataLanguage != "en", metadata.descriptionLanguage != locale.metadataLanguage {
            refreshLock.lock()
            let retryAfter = descriptionRetryAfter[metadata.titleId + "/" + locale.metadataLanguage]
            refreshLock.unlock()
            guard metadata.descriptionCheckedAt.map({ now.timeIntervalSince($0) < 24 * 3600 }) == true
                    || retryAfter.map({ now < $0 }) == true else { return false }
        }
        guard metadata.screenshotURLs.isEmpty, Self.looksLikeTitleDBID(metadata.titleId) else { return true }
        refreshLock.lock()
        defer { refreshLock.unlock() }
        return screenshotRefreshTried.contains(metadata.titleId + "/" + locale.metadataLanguage)
    }

    /// Synchronous so the lock is never held across a suspension point.
    private func markScreenshotRefreshTried(_ titleId: String) {
        refreshLock.lock()
        defer { refreshLock.unlock() }
        screenshotRefreshTried.insert(titleId)
    }

    private static func looksLikeTitleDBID(_ id: String) -> Bool {
        id.count == 16 && (id.hasPrefix("0100") || id.hasPrefix("0400")) && id.allSatisfy(\.isHexDigit)
    }

    public func metadata(for game: PortedGame, locale: AppLocale = AppLocale(language: .english, region: "US")) async throws -> NintendoStoreMetadata {
        let key = game.titleId ?? game.uniqueKey
        let previous = cached(for: key, locale: locale)
        if let cached = cached(for: key, locale: locale) {
            if isFresh(cached, locale: locale) { return cached }
            if cached.screenshotURLs.isEmpty, Self.looksLikeTitleDBID(cached.titleId) {
                markScreenshotRefreshTried(cached.titleId + "/" + locale.metadataLanguage)
            }
        }

        // A language switch reuses fresh artwork and credits; only the description needs a request.
        if locale.metadataLanguage != "en", var base = previous ?? cached(for: key),
           Date().timeIntervalSince(base.fetchedAt) < Self.ttl {
            let item = await fetchTitleDBItem(titleId: key, language: locale.metadataLanguage)
            applyDescription(item, to: &base, locale: locale)
            if let item { Self.fill(&base, from: item) }
            markScreenshotRefreshTried(key + "/" + locale.metadataLanguage)
            base.localeKey = locale.cacheKey
            try? cache(base, for: key, locale: locale)
            return base
        }

        do {
            var metadata: NintendoStoreMetadata
            do { metadata = try await fetch(game: game, cacheKey: key) }
            catch {
                guard locale.metadataLanguage != "en",
                      let localized = await fetchTitleDB(titleId: key, language: locale.metadataLanguage),
                      !localized.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw error }
                metadata = localized
                metadata.descriptionLanguage = locale.metadataLanguage
                metadata.descriptionCheckedAt = Date()
            }
            if locale.metadataLanguage != "en", metadata.descriptionLanguage != locale.metadataLanguage {
                let item = await fetchTitleDBItem(titleId: key, language: locale.metadataLanguage)
                applyDescription(item, to: &metadata, locale: locale)
            }
            if metadata.descriptionLanguage != locale.metadataLanguage,
               let previous, previous.descriptionLanguage == locale.metadataLanguage,
               !previous.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.description = previous.description
                metadata.descriptionLanguage = previous.descriptionLanguage
                metadata.fetchedAt = min(metadata.fetchedAt, previous.fetchedAt)
            }
            metadata.localeKey = locale.cacheKey
            try? cache(metadata, for: key, locale: locale)
            return metadata
        } catch {
            // A stale cache is still better than an empty panel when Nintendo is
            // unreachable; the UI shows the fetched date.
            if let cached = cached(for: key, locale: locale) { return cached }
            if locale.cacheKey != "en_US", let english = cached(for: key) { return english }
            throw error
        }
    }

    private func applyDescription(_ item: TitleDBItem?, to metadata: inout NintendoStoreMetadata, locale: AppLocale) {
        if let item {
            metadata.descriptionCheckedAt = Date()
            if let text = item.description?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
               text != metadata.description.trimmingCharacters(in: .whitespacesAndNewlines)
                    || metadata.descriptionLanguage == locale.metadataLanguage {
                metadata.description = text
                metadata.descriptionLanguage = locale.metadataLanguage
            }
        } else {
            // A transient network failure is retried soon; it is not persisted as a missing translation.
            refreshLock.lock()
            descriptionRetryAfter[metadata.titleId + "/" + locale.metadataLanguage] = Date().addingTimeInterval(60)
            refreshLock.unlock()
        }
    }

    private func fetch(game: PortedGame, cacheKey: String) async throws -> NintendoStoreMetadata {
        var titleDBUsed = false
        var meta = try await fetchStore(game: game, cacheKey: cacheKey, titleDBUsed: &titleDBUsed)
        if !titleDBUsed, let item = await fetchTitleDBItem(titleId: cacheKey) {
            Self.fill(&meta, from: item)
        }
        return meta
    }

    /// Fills only what the store path left empty; never overwrites store data.
    private static func fill(_ meta: inout NintendoStoreMetadata, from item: TitleDBItem) {
        if meta.screenshotURLs.isEmpty { meta.screenshotURLs = item.screenshotURLs }
        if meta.genres.isEmpty { meta.genres = item.genres }
        if meta.developers.isEmpty, let dev = item.developer, !dev.isEmpty {
            meta.developers = [dev]
        }
        if meta.releaseDate == nil { meta.releaseDate = item.releaseDateString }
    }

    private func fetchStore(game: PortedGame, cacheKey: String,
                            titleDBUsed: inout Bool) async throws -> NintendoStoreMetadata {
        // Older games are fully described in the legacy catalog. Try it first:
        // one request and no product-page download.
        if let old = try? await searchOld(name: game.name),
           let hit = chooseOld(old, name: game.name, titleId: cacheKey) {
            var meta = metadata(from: hit, titleId: cacheKey)
            if meta.headerImageURL == nil && cacheKey.count == 16 && cacheKey.hasPrefix("0100") {
                meta.headerImageURL = URL(string: "https://api.nlib.cc/nx/\(cacheKey)/banner")
            }
            return meta
        }

        let newHits = (try? await searchNew(name: game.name)) ?? []
        guard let hit = chooseNew(newHits, name: game.name, titleId: cacheKey),
              let urlPath = hit.url,
              let storeURL = URL(string: urlPath.hasPrefix("http") ? urlPath
                                 : "https://www.nintendo.com\(urlPath)") else {
            titleDBUsed = true
            if let fromTitleDB = await fetchTitleDB(titleId: cacheKey) {
                return fromTitleDB
            }
            throw NintendoStoreError.notFound
        }

        if let old = try? await searchOld(name: game.name),
           let oldHit = chooseOld(old, name: game.name, titleId: cacheKey) {
            var meta = metadata(from: oldHit, titleId: cacheKey, storeURL: storeURL)
            if meta.headerImageURL == nil && cacheKey.count == 16 && cacheKey.hasPrefix("0100") {
                meta.headerImageURL = URL(string: "https://api.nlib.cc/nx/\(cacheKey)/banner")
            }
            return meta
        }

        let page = try await fetchProductPage(storeURL)
        var meta = metadata(from: page, titleId: cacheKey, storeURL: storeURL,
                            newHit: hit)
        if meta.headerImageURL == nil && cacheKey.count == 16 && cacheKey.hasPrefix("0100") {
            meta.headerImageURL = URL(string: "https://api.nlib.cc/nx/\(cacheKey)/banner")
        }
        return meta
    }

    private struct TitleDBItem: Decodable {
        struct Screens: Decodable {
            let count: Int?
            let screenshots: [String]?
        }
        let id: String?
        let name: String?
        let publisher: String?
        let description: String?
        let banner: String?
        let icon: String?
        let screens: Screens?
        let releaseDate: String?
        let developer: String?
        let category: [String]?

        private enum CodingKeys: String, CodingKey {
            case id, name, publisher, description, banner, icon, screens, releaseDate, developer, category
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try? c.decodeIfPresent(String.self, forKey: .id)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            publisher = try? c.decodeIfPresent(String.self, forKey: .publisher)
            description = try? c.decodeIfPresent(String.self, forKey: .description)
            banner = try? c.decodeIfPresent(String.self, forKey: .banner)
            icon = try? c.decodeIfPresent(String.self, forKey: .icon)
            screens = try? c.decodeIfPresent(Screens.self, forKey: .screens)
            developer = try? c.decodeIfPresent(String.self, forKey: .developer)
            category = try? c.decodeIfPresent([String].self, forKey: .category)
            // titledb sends either "2017-03-03" or an integer like 20170303.
            if let text = try? c.decodeIfPresent(String.self, forKey: .releaseDate) {
                releaseDate = text
            } else if let number = try? c.decodeIfPresent(Int.self, forKey: .releaseDate) {
                releaseDate = String(number)
            } else {
                releaseDate = nil
            }
        }

        var screenshotURLs: [URL] {
            (screens?.screenshots ?? []).compactMap { raw in
                var text = raw
                if text.hasPrefix("http://api.nlib.cc") {
                    text = "https://" + text.dropFirst("http://".count)
                }
                return URL(string: text)
            }
        }

        var genres: [String] { (category ?? []).filter { $0 != "Other" } }

        /// "yyyy-MM-dd" as stored; compact 8-digit integers are reformatted.
        var releaseDateString: String? {
            guard let raw = releaseDate?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
                return nil
            }
            let parse = DateFormatter()
            parse.locale = Locale(identifier: "en_US_POSIX")
            parse.timeZone = TimeZone(identifier: "UTC")
            parse.dateFormat = raw.count == 8 && Int(raw) != nil ? "yyyyMMdd" : "yyyy-MM-dd"
            guard let date = parse.date(from: String(raw.prefix(raw.count == 8 ? 8 : 10))) else {
                return nil
            }
            parse.dateFormat = "yyyy-MM-dd"
            return parse.string(from: date)
        }
    }

    private func fetchTitleDBItem(titleId: String, language: String = "en") async -> TitleDBItem? {
        guard Self.looksLikeTitleDBID(titleId),
              let url = URL(string: "https://api.nlib.cc/nx/\(titleId)?fields=name,publisher,description,banner,icon,screens,releaseDate,developer,category&lang=\(language)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (data, response) = try await client.data(for: request)
            guard (200..<300).contains(response.statusCode) else { return nil }
            return try JSONDecoder().decode(TitleDBItem.self, from: data)
        } catch {
            return nil
        }
    }

    private func fetchTitleDB(titleId: String, language: String = "en") async -> NintendoStoreMetadata? {
        guard let item = await fetchTitleDBItem(titleId: titleId, language: language),
              let name = item.name, !name.isEmpty else { return nil }
        return NintendoStoreMetadata(
            titleId: titleId,
            name: name,
            description: item.description ?? "",
            developers: item.developer.flatMap { $0.isEmpty ? nil : [$0] } ?? [],
            publishers: item.publisher.map { [$0] } ?? [],
            genres: item.genres,
            releaseDate: item.releaseDateString,
            storeURL: URL(string: "https://www.nintendo.com")!,
            imageURL: item.icon.flatMap(URL.init(string:)),
            headerImageURL: item.banner.flatMap(URL.init(string:)) ?? URL(string: "https://api.nlib.cc/nx/\(titleId)/banner"),
            logoURL: nil,
            nsuid: nil,
            fetchedAt: Date(),
            screenshotURLs: item.screenshotURLs
        )
    }

    // MARK: - Nintendo Store searches

    private struct SearchBody: Encodable {
        let query: String
        let hitsPerPage: Int
    }

    private func searchNew(name: String) async throws -> [NewHit] {
        let data = try await post(
            index: Self.newIndex, key: Self.newKey,
            body: SearchBody(query: name, hitsPerPage: 12)
        )
        guard let response = try? JSONDecoder().decode(NewResponse.self, from: data) else {
            throw NintendoStoreError.decoding
        }
        return response.hits
    }

    private func searchOld(name: String) async throws -> [OldHit] {
        let data = try await post(
            index: Self.oldIndex, key: Self.oldKey,
            body: SearchBody(query: name, hitsPerPage: 50)
        )
        guard let response = try? JSONDecoder().decode(OldResponse.self, from: data) else {
            throw NintendoStoreError.decoding
        }
        return response.hits
    }

    private func post<T: Encodable>(index: String, key: String, body: T) async throws -> Data {
        guard let url = URL(string: "https://\(Self.appID)-dsn.algolia.net/1/indexes/\(index)/query") else {
            throw NintendoStoreError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(Self.appID, forHTTPHeaderField: "X-Algolia-Application-Id")
        request.setValue(key, forHTTPHeaderField: "X-Algolia-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("NXLibrary/0.1 (macOS; personal app)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, http) = try await client.data(for: request)
        guard (200..<300).contains(http.statusCode) else {
            throw NintendoStoreError.http(http.statusCode)
        }
        return data
    }

    // MARK: - Product page

    private func fetchProductPage(_ url: URL) async throws -> PageProduct {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("NXLibrary/0.1 (macOS; personal app)", forHTTPHeaderField: "User-Agent")
        let (data, http) = try await client.data(for: request)
        guard (200..<300).contains(http.statusCode) else {
            throw NintendoStoreError.http(http.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8),
              let range = html.range(of: "<script id=\"__NEXT_DATA__\" type=\"application/json\">"),
              let end = html.range(of: "</script>", range: range.upperBound..<html.endIndex) else {
            throw NintendoStoreError.decoding
        }
        let json = String(html[range.upperBound..<end.lowerBound])
        guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let props = root["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let state = pageProps["initialApolloState"] as? [String: Any] else {
            throw NintendoStoreError.decoding
        }

        let target = Self.normalize(url.lastPathComponent)
        var candidates: [PageProduct] = []
        for (key, value) in state where key.hasPrefix("Product:") {
            guard let dict = value as? [String: Any],
                  let name = dict["name"] as? String,
                  let description = dict["description"] as? String,
                  !description.isEmpty else { continue }
            let normalized = Self.normalize(name)
            guard normalized == target || normalized.contains(target) || target.contains(normalized) else { continue }
            let tags = (dict["tags"] as? [String: Any])?["genres"] as? [[String: Any]] ?? []
            let genres = tags.compactMap { $0["label"] as? String }
            let image = (dict["productImage"] as? [String: Any])?["url"] as? String
            var publisher: String? = nil
            if let linkedArray = pageProps["linkedData"] as? [Any],
               let linked = linkedArray.first as? [String: Any],
               let publisherObject = linked["publisher"] as? [String: Any] {
                publisher = publisherObject["name"] as? String
            }
            candidates.append(PageProduct(
                name: name,
                description: Self.plainText(description),
                genres: genres,
                publisher: publisher,
                releaseDate: dict["releaseDate"] as? String,
                imageURL: image.flatMap(URL.init(string:))
            ))
        }
        guard let best = candidates.first(where: { Self.normalize($0.name) == target })
                ?? candidates.first else {
            throw NintendoStoreError.notFound
        }
        return best
    }

    // MARK: - Mapping

    private func metadata(from old: OldHit, titleId: String,
                          storeURL: URL? = nil) -> NintendoStoreMetadata {
        let path = old.url ?? ""
        let url = storeURL ?? URL(string: path.hasPrefix("http") ? path
                                  : "https://www.nintendo.com\(path)")
        return NintendoStoreMetadata(
            titleId: titleId,
            name: old.title ?? "Unknown game",
            description: Self.plainText(old.description ?? ""),
            developers: old.developers ?? [],
            publishers: old.publishers ?? [],
            genres: old.genres ?? [],
            releaseDate: old.releaseDateDisplay,
            storeURL: url ?? URL(string: "https://www.nintendo.com")!,
            imageURL: old.boxart.flatMap(URL.init(string:)),
            headerImageURL: old.horizontalHeaderImage.flatMap(URL.init(string:)),
            nsuid: old.nsuid,
            fetchedAt: Date()
        )
    }

    private func metadata(from page: PageProduct, titleId: String,
                          storeURL: URL, newHit: NewHit) -> NintendoStoreMetadata {
        NintendoStoreMetadata(
            titleId: titleId,
            name: page.name,
            description: page.description,
            developers: [],
            publishers: page.publisher.map { [$0] } ?? [],
            genres: page.genres,
            releaseDate: page.releaseDate,
            storeURL: storeURL,
            imageURL: nil,
            headerImageURL: page.imageURL,
            nsuid: newHit.nsuid,
            fetchedAt: Date()
        )
    }

    /// The store's platforms, the game's own first: a Switch 2 title ID starts with 04. A game sold for both
    /// (a Nintendo Switch 2 Edition) then gets the page of the version that was ported.
    static func platforms(forTitleId titleId: String) -> [String] {
        titleId.hasPrefix("04") ? ["Nintendo Switch 2", "Nintendo Switch"] : ["Nintendo Switch", "Nintendo Switch 2"]
    }

    static func ordered<Hit>(_ hits: [Hit], platform: (Hit) -> String?, titleId: String) -> [Hit] {
        let order = platforms(forTitleId: titleId)
        return order.flatMap { wanted in hits.filter { platform($0) == wanted } }
    }

    private func chooseNew(_ hits: [NewHit], name: String, titleId: String) -> NewHit? {
        let target = Self.normalize(name)
        let games = Self.ordered(hits.filter {
            ($0.topLevelCategory ?? "").caseInsensitiveCompare("Games") == .orderedSame
                && $0.url != nil
        }, platform: \.platform, titleId: titleId)
        return games.first { Self.normalize($0.title ?? "") == target }
            ?? games.first {
                let title = Self.normalize($0.title ?? "")
                return title.contains(target) || target.contains(title)
            }
            ?? games.first
    }

    private func chooseOld(_ hits: [OldHit], name: String, titleId: String) -> OldHit? {
        let target = Self.normalize(name)
        let games = Self.ordered(hits.filter { !($0.description ?? "").isEmpty },
                                 platform: \.platform, titleId: titleId)
        return games.first { Self.normalize($0.title ?? "") == target }
            ?? games.first {
                let title = Self.normalize($0.title ?? "")
                return title.contains(target) || target.contains(title)
            }
    }

    // MARK: - Cache and text

    public func cacheSize() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            guard values?.isDirectory != true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    public func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
    }

    private func cacheURL(for titleId: String, locale: AppLocale) -> URL {
        let folder = locale.cacheKey == "en_US" ? cacheDirectory
            : cacheDirectory.appendingPathComponent("localized/\(locale.cacheKey)")
        return folder.appendingPathComponent(Self.safeFileName(titleId) + ".json")
    }

    private func cache(_ metadata: NintendoStoreMetadata, for titleId: String, locale: AppLocale) throws {
        let url = cacheURL(for: titleId, locale: locale)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: url, options: .atomic)
    }

    private static func safeFileName(_ value: String) -> String {
        value.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
            .reduce(into: "") { $0.append($1) }
    }

    static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "™", with: "")
            .replacingOccurrences(of: "®", with: "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func plainText(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
            "&lt;": "<", "&gt;": ">"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Wire types

    private struct NewResponse: Decodable { let hits: [NewHit] }
    private struct OldResponse: Decodable { let hits: [OldHit] }

    private struct NewHit: Decodable {
        let title: String?
        let nsuid: String?
        let platform: String?
        let url: String?
        let topLevelCategory: String?
    }

    private struct OldHit: Decodable {
        let title: String?
        let nsuid: String?
        let description: String?
        let developers: [String]?
        let publishers: [String]?
        let genres: [String]?
        let releaseDateDisplay: String?
        let url: String?
        let boxart: String?
        let horizontalHeaderImage: String?
        let platform: String?
    }

    private struct PageProduct {
        let name: String
        let description: String
        let genres: [String]
        let publisher: String?
        let releaseDate: String?
        let imageURL: URL?
    }
}
