import Foundation
import CryptoKit

/// Keyless, on-demand enrichment for Details. Cache and failures never alter the catalog.
public actor CriticRatingService {
    public typealias Transport = @Sendable (URL) async throws -> Data
    public static let shared = CriticRatingService()
    private let directory: URL
    private let transport: Transport
    private struct Cache: Codable {
        let query: CriticRatingQuery
        let rating: CriticRating?
        let fetchedAt: Date
        let resolverVersion: Int?
    }
    private struct Flight {
        let id: UUID
        let task: Task<CriticRatingResult, Never>
        var waiters: Set<UUID>
    }
    private var pending: [CriticRatingQuery: Flight] = [:]
    private var requestTail: Task<Void, Never>?
    private var backoffUntil = Date.distantPast

    public init(directory: URL = AppData.supportRoot.appendingPathComponent("ratings/wikidata"),
                transport: @escaping Transport = { try await CriticRatingService.download($0) }) {
        self.directory = directory
        self.transport = transport
    }
    /// IGDB critics, public critics, then explicitly identified IGDB community scores.
    public func preferred(_ query: CriticRatingQuery, credentials: IGDBCredentials?,
                          igdb: IGDBRatingService = .shared) async -> CriticRatingResult {
        var community: CriticRatingResult?
        if let credentials {
            let primary = await igdb.load(query, credentials: credentials)
            if !Task.isCancelled, let rating = primary.rating {
                if !rating.isCommunity { return primary }
                community = primary
            }
        }
        let fallback = await load(query)
        guard !Task.isCancelled else { return CriticRatingResult(rating: nil, fetchedAt: nil, isStale: false) }
        return fallback.rating != nil ? fallback : (community ?? fallback)
    }
    public func load(_ query: CriticRatingQuery, now: Date = Date()) async -> CriticRatingResult {
        let empty = CriticRatingResult(rating: nil, fetchedAt: nil, isStale: false)
        guard !Task.isCancelled, !query.name.isEmpty, query.name.count <= 300 else { return empty }
        let waiter = UUID()
        var flight: Flight
        if let current = pending[query] { flight = current; flight.waiters.insert(waiter) }
        else {
            guard pending.count < 4 else { return empty }
            flight = Flight(id: UUID(), task: Task { await self.resolve(query, now: now) }, waiters: [waiter])
        }
        pending[query] = flight
        let task = flight.task, id = flight.id
        return await withTaskCancellationHandler(operation: {
            defer { release(query, id: id, waiter: waiter) }
            let result = await task.value
            return Task.isCancelled ? empty : result
        }, onCancel: { Task { await self.release(query, id: id, waiter: waiter) } })
    }
    private func release(_ query: CriticRatingQuery, id: UUID, waiter: UUID) {
        guard var flight = pending[query], flight.id == id else { return }
        flight.waiters.remove(waiter)
        if flight.waiters.isEmpty { flight.task.cancel(); pending[query] = nil }
        else { pending[query] = flight }
    }
    private func resolve(_ query: CriticRatingQuery, now: Date) async -> CriticRatingResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let key = SHA256.hash(data: (try? encoder.encode(query)) ?? Data())
            .map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent(key + ".json")
        let cached = (try? InstallationFileSnapshot.read(at: file, maximumBytes: 65_536).data)
            .flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
            .flatMap { $0.query == query && ($0.rating?.isValid ?? true)
                && ($0.rating != nil || $0.resolverVersion == 2) ? $0 : nil }
        func result(_ cache: Cache?, stale: Bool) -> CriticRatingResult {
            CriticRatingResult(rating: cache?.rating, fetchedAt: cache?.fetchedAt, isStale: stale && cache != nil)
        }
        let age = cached.map { now.timeIntervalSince($0.fetchedAt) }
        let ttl: TimeInterval = cached?.rating == nil ? 86400 : 7 * 86400
        if let age, age >= 0, age < ttl { return result(cached, stale: false) }
        guard Date() >= backoffUntil else { return result(cached, stale: true) }
        do {
            try Task.checkCancellation()
            var ids: [String] = []
            if let appID = query.steamAppID, let url = WikidataRatings.steamSearchURL(appID: appID) {
                ids = try WikidataRatings.steamIDs(in: await fetch(url))
            }
            let bySteamID = !ids.isEmpty
            if ids.isEmpty {
                guard let searchURL = WikidataRatings.searchURL(name: query.name) else { return result(cached, stale: true) }
                let search = try await fetch(searchURL)
                ids = try WikidataRatings.ids(in: search, name: query.name)
            }
            var rating: CriticRating?
            if let url = WikidataRatings.entitiesURL(ids: ids) {
                let data = try await fetch(url)
                rating = try WikidataRatings.rating(in: data, ids: ids, query: query, requireSteamID: bySteamID)
            }
            try Task.checkCancellation()
            let value = Cache(query: query, rating: rating, fetchedAt: now, resolverVersion: 2)
            // An unwritable cache does not discard a valid network answer.
            if let encoded = try? JSONEncoder().encode(value), encoded.count <= 65_536 {
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try encoded.write(to: file, options: .atomic)
                } catch { /* Enrichment remains usable in memory for this appearance. */ }
            }
            return result(value, stale: false)
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { backoffUntil = Date().addingTimeInterval(60) }
            return result(cached, stale: true)
        }
    }
    /// Requests are serial across games, as requested by MediaWiki's API etiquette.
    private func fetch(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        let previous = requestTail, transport = transport
        let request = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await transport(url)
        }
        requestTail = Task { _ = try? await request.value }
        return try await withTaskCancellationHandler(operation: {
            let data = try await request.value
            try Task.checkCancellation()
            return data
        }, onCancel: { request.cancel() })
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    /// Ephemeral, one connection per host, no redirects: shared with `WikipediaDescriptionService`.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 20
        config.timeoutIntervalForRequest = 12
        config.httpMaximumConnectionsPerHost = 1
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()
    public static func download(_ url: URL) async throws -> Data {
        guard url.scheme == "https", url.host == "www.wikidata.org", url.path == "/w/api.php",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(AppIdentity.userAgent(), forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await BoundedDownload.data(for: request, session: session, limit: 4_194_304)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.url == url else { throw URLError(.badServerResponse) }
        return data
    }
}
