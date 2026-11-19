import CryptoKit
import Foundation
import NaturalLanguage

/// A game's introduction from Wikipedia in the player's language, shown in About this game when the store has no
/// text in that language. Licensed CC BY-SA: the page link travels with the text and is shown beside it.
public struct WikipediaDescription: Codable, Equatable, Sendable {
    public let text: String
    public let pageURL: URL
}

/// Narrow contract: the same Wikidata identity as critic ratings (`WikidataRatings.entity`), its sitelink to the
/// player's Wikipedia, and that article's plain-text introduction.
public enum WikipediaDescriptions {
    /// Shorter texts are too uncertain to name a language.
    static let minimumLength = 40
    static let minimumConfidence = 0.6

    /// The Wikipedia edition for `language`, and the script variant its text is converted to.
    public static func edition(for language: AppLanguage) -> (code: String, variant: String?)? {
        switch language {
        case .automatic: return nil
        case .chineseSimplified: return ("zh", "zh-cn")
        case .portugueseBrazil: return ("pt", nil)
        default: return (language.rawValue, nil)
        }
    }

    /// Whether About this game should look for Wikipedia's text: the description is empty, or written in another
    /// language than the app's. A description the player chose (`"custom"`) is never replaced.
    public static func wanted(description: String, descriptionLanguage: String?, language: AppLanguage) -> Bool {
        guard edition(for: language) != nil, descriptionLanguage != "custom" else { return false }
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return true }
        guard let tag = detectLanguage(of: text) else { return false }
        return !matches(tag, language)
    }

    /// A BCP 47 tag ("en", "zh-Hans"), or nil when the text is short or no language clearly leads.
    static func detectLanguage(of text: String) -> String? {
        guard text.count >= minimumLength else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              language != .undetermined, confidence >= minimumConfidence else { return nil }
        return language.rawValue
    }

    /// Languages compare by base code (pt is pt-BR); Chinese by script too, so Traditional text is not Simplified.
    static func matches(_ tag: String, _ language: AppLanguage) -> Bool {
        let base = { (value: String) in value.split(separator: "-").first.map(String.init) ?? value }
        if language == .chineseSimplified { return tag == "zh-Hans" || tag == "zh" }
        return base(tag) == base(language.rawValue)
    }

    /// The article title on `code`.wikipedia for the game the query names, or nil when it has none.
    public static func sitelink(in data: Data, ids: [String], query: CriticRatingQuery, requireSteamID: Bool,
                                edition code: String) throws -> String? {
        guard let (_, entity) = try WikidataRatings.entity(in: data, ids: ids, query: query, requireSteamID: requireSteamID),
              let links = entity["sitelinks"] as? [String: [String: Any]],
              let title = links[code + "wiki"]?["title"] as? String, !title.isEmpty, title.count <= 300 else { return nil }
        return title
    }

    public static func introURL(edition code: String, title: String, variant: String?) -> URL? {
        guard allowedEditions.contains(code), !title.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = code + ".wikipedia.org"
        components.path = "/w/api.php"
        var items = ["action": "query", "prop": "extracts|info", "exintro": "1", "explaintext": "1",
                     "inprop": "url", "redirects": "1", "format": "json", "formatversion": "2", "titles": title]
        if let variant { items["variant"] = variant }
        components.queryItems = items.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        return components.url
    }

    /// The introduction as plain text, with its page; nil for a missing page or an empty introduction.
    public static func description(in data: Data, edition code: String) throws -> WikipediaDescription? {
        let root = try WikidataRatings.object(data)
        guard let query = root["query"] as? [String: Any], let pages = query["pages"] as? [[String: Any]]
        else { throw URLError(.cannotParseResponse) }
        guard let page = pages.first, page["missing"] == nil,
              let raw = page["extract"] as? String,
              let link = (page["fullurl"] as? String).flatMap(URL.init(string:)),
              link.scheme == "https", link.host == code + ".wikipedia.org" else { return nil }
        let text = raw.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard text.count >= minimumLength else { return nil }
        return WikipediaDescription(text: text, pageURL: link)
    }

    static let allowedEditions: Set<String> = ["en", "it", "fr", "de", "es", "pt", "zh"]
}

/// Keyless, on-demand Wikipedia introductions for About this game. Cache and failures never alter the catalog or
/// the store metadata: the text is only what the page shows.
public actor WikipediaDescriptionService {
    public typealias Transport = @Sendable (URL) async throws -> Data
    public static let shared = WikipediaDescriptionService()

    private struct Cache: Codable {
        let query: CriticRatingQuery
        let language: String
        let description: WikipediaDescription?
        let fetchedAt: Date
        var version = 1
    }

    private let directory: URL
    private let transport: Transport
    private var pending: [String: Task<WikipediaDescription?, Never>] = [:]
    private var backoffUntil = Date.distantPast

    public init(directory: URL = AppData.supportRoot.appendingPathComponent("descriptions/wikipedia"),
                transport: @escaping Transport = { try await WikipediaDescriptionService.download($0) }) {
        self.directory = directory
        self.transport = transport
    }

    public func load(_ query: CriticRatingQuery, language: AppLanguage, now: Date = Date()) async -> WikipediaDescription? {
        guard !query.name.isEmpty, query.name.count <= 300, WikipediaDescriptions.edition(for: language) != nil else { return nil }
        let key = Self.key(query, language)
        if let current = pending[key] { return await current.value }
        let task = Task { await resolve(query, language: language, key: key, now: now) }
        pending[key] = task
        let result = await task.value
        pending[key] = nil
        return result
    }

    /// Bytes on disk, counted in Storage → Metadata cache with the store's descriptions.
    public nonisolated func cacheSize() -> Int64 {
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        return (files?.allObjects as? [URL] ?? []).reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    /// Forgets every saved introduction and "no article"; the next page asks Wikipedia again.
    public nonisolated func clearCache() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func key(_ query: CriticRatingQuery, _ language: AppLanguage) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = ((try? encoder.encode(query)) ?? Data()) + Data(language.rawValue.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func resolve(_ query: CriticRatingQuery, language: AppLanguage, key: String, now: Date) async -> WikipediaDescription? {
        guard let edition = WikipediaDescriptions.edition(for: language) else { return nil }
        let file = directory.appendingPathComponent(key + ".json")
        let cached = (try? InstallationFileSnapshot.read(at: file, maximumBytes: 262_144).data)
            .flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
            .flatMap { $0.query == query && $0.language == language.rawValue ? $0 : nil }
        if let cached {
            let age = now.timeIntervalSince(cached.fetchedAt)
            // A page found is kept for a month; "no article" is asked again the next day.
            let ttl: TimeInterval = cached.description == nil ? 86_400 : 30 * 86_400
            if age >= 0, age < ttl { return cached.description }
        }
        guard Date() >= backoffUntil else { return cached?.description }
        do {
            var ids: [String] = []
            if let appID = query.steamAppID, let url = WikidataRatings.steamSearchURL(appID: appID) {
                ids = try WikidataRatings.steamIDs(in: await transport(url))
            }
            let bySteamID = !ids.isEmpty
            if ids.isEmpty, let url = WikidataRatings.searchURL(name: query.name) {
                ids = try WikidataRatings.ids(in: await transport(url), name: query.name)
            }
            var found: WikipediaDescription?
            if let url = WikidataRatings.entitiesURL(ids: ids, props: "claims|sitelinks"),
               let title = try WikipediaDescriptions.sitelink(in: await transport(url), ids: ids, query: query,
                                                             requireSteamID: bySteamID, edition: edition.code),
               let intro = WikipediaDescriptions.introURL(edition: edition.code, title: title, variant: edition.variant) {
                found = try WikipediaDescriptions.description(in: await transport(intro), edition: edition.code)
            }
            try Task.checkCancellation()
            let value = Cache(query: query, language: language.rawValue, description: found, fetchedAt: now)
            // An unwritable cache does not discard a valid answer.
            if let encoded = try? JSONEncoder().encode(value), encoded.count <= 262_144 {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? encoded.write(to: file, options: .atomic)
            }
            return found
        } catch {
            // A network error is never saved as "no article".
            if !(error is CancellationError) { backoffUntil = Date().addingTimeInterval(60) }
            return cached?.description
        }
    }

    public static func download(_ url: URL) async throws -> Data {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              url.path == "/w/api.php", let host = url.host,
              host == "www.wikidata.org" || WikipediaDescriptions.allowedEditions.contains(where: { host == $0 + ".wikipedia.org" })
        else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(AppIdentity.userAgent(), forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await BoundedDownload.data(for: request, session: CriticRatingService.session, limit: 4_194_304)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.url == url else { throw URLError(.badServerResponse) }
        return data
    }
}
