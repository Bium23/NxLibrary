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
    public var nsuid: String?
    public var fetchedAt: Date

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
        case .notFound: return "No Nintendo Store entry was found for this game."
        case .invalidURL: return "The Nintendo Store URL is invalid."
        case .http(let status): return "Nintendo Store returned status \(status)."
        case .decoding: return "Nintendo Store returned a response this app could not read."
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

    public func cached(for titleId: String) -> NintendoStoreMetadata? {
        guard let data = try? Data(contentsOf: cacheURL(for: titleId)) else { return nil }
        return try? JSONDecoder().decode(NintendoStoreMetadata.self, from: data)
    }

    public func metadata(for game: PortedGame) async throws -> NintendoStoreMetadata {
        let key = game.titleId ?? game.uniqueKey
        if let cached = cached(for: key),
           Date().timeIntervalSince(cached.fetchedAt) < Self.ttl {
            return cached
        }

        do {
            let metadata = try await fetch(game: game, cacheKey: key)
            try? cache(metadata, for: key)
            return metadata
        } catch {
            // A stale cache is still better than an empty panel when Nintendo is
            // unreachable; the UI shows the fetched date.
            if let cached = cached(for: key) { return cached }
            throw error
        }
    }

    private func fetch(game: PortedGame, cacheKey: String) async throws -> NintendoStoreMetadata {
        // Older games are fully described in the legacy catalog. Try it first:
        // one request and no product-page download.
        if let old = try? await searchOld(name: game.name),
           let hit = chooseOld(old, name: game.name) {
            return metadata(from: hit, titleId: cacheKey)
        }

        let newHits = try await searchNew(name: game.name)
        guard let hit = chooseNew(newHits, name: game.name),
              let urlPath = hit.url,
              let storeURL = URL(string: urlPath.hasPrefix("http") ? urlPath
                                 : "https://www.nintendo.com\(urlPath)") else {
            throw NintendoStoreError.notFound
        }

        if let old = try? await searchOld(name: game.name),
           let oldHit = chooseOld(old, name: game.name) {
            return metadata(from: oldHit, titleId: cacheKey, storeURL: storeURL)
        }

        let page = try await fetchProductPage(storeURL)
        return metadata(from: page, titleId: cacheKey, storeURL: storeURL,
                        newHit: hit)
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

    private func chooseNew(_ hits: [NewHit], name: String) -> NewHit? {
        let target = Self.normalize(name)
        let games = hits.filter {
            ($0.topLevelCategory ?? "").caseInsensitiveCompare("Games") == .orderedSame
                && ($0.platform ?? "") == "Nintendo Switch"
                && $0.url != nil
        }
        return games.first { Self.normalize($0.title ?? "") == target }
            ?? games.first {
                let title = Self.normalize($0.title ?? "")
                return title.contains(target) || target.contains(title)
            }
            ?? games.first
    }

    private func chooseOld(_ hits: [OldHit], name: String) -> OldHit? {
        let target = Self.normalize(name)
        let games = hits.filter {
            ($0.platform ?? "") == "Nintendo Switch"
                && !($0.description ?? "").isEmpty
        }
        return games.first { Self.normalize($0.title ?? "") == target }
            ?? games.first {
                let title = Self.normalize($0.title ?? "")
                return title.contains(target) || target.contains(title)
            }
    }

    // MARK: - Cache and text

    private func cacheURL(for titleId: String) -> URL {
        cacheDirectory.appendingPathComponent(Self.safeFileName(titleId) + ".json")
    }

    private func cache(_ metadata: NintendoStoreMetadata, for titleId: String) throws {
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: cacheURL(for: titleId), options: .atomic)
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
