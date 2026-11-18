import Foundation

/// Two bounded public-page lookups, isolated from artwork downloads and personal choices.
public actor DatabaseMetadataService {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private static let launchBox = DatabaseMetadataService(database: .launchBox)
    private static let theGamesDB = DatabaseMetadataService(database: .theGamesDB)
    public static func shared(_ database: MetadataDatabase) -> DatabaseMetadataService {
        database == .launchBox ? launchBox : theGamesDB
    }
    private let database: MetadataDatabase
    private let directory: URL
    private let transport: Transport
    private struct Cache: Codable {
        let query: CriticRatingQuery
        let preview: DatabaseMetadataPreview?
        let issue: DatabaseMetadataIssue?
        let fetchedAt: Date
    }
    private struct Flight {
        let id: UUID
        let task: Task<DatabaseMetadataResult, Never>
        var waiters: Set<UUID>
    }
    private var pending: [CriticRatingQuery: Flight] = [:]

    public init(database: MetadataDatabase, directory: URL = AppData.supportRoot.appendingPathComponent("metadata/databases"),
                transport: Transport? = nil) {
        self.database = database; self.directory = directory.appendingPathComponent(database.rawValue)
        self.transport = transport ?? { try await DatabaseMetadataService.download($0) }
    }
    public func load(_ query: CriticRatingQuery, now: Date = Date(), forceRefresh: Bool = false) async -> DatabaseMetadataResult {
        guard !Task.isCancelled else { return .missing(.cancelled) }
        guard !query.name.isEmpty, query.name.count <= 300 else { return .missing(.notFound) }
        let waiter = UUID()
        var flight: Flight
        if let saved = pending[query] { flight = saved; flight.waiters.insert(waiter) }
        else {
            guard pending.count < 4 else { return .missing(.unavailable) }
            flight = Flight(id: UUID(), task: Task { await self.resolve(query, now: now, forceRefresh: forceRefresh) }, waiters: [waiter])
        }
        pending[query] = flight
        let id = flight.id, task = flight.task
        return await withTaskCancellationHandler(operation: {
            defer { release(query, id: id, waiter: waiter) }
            let result = await task.value
            return Task.isCancelled ? .missing(.cancelled) : result
        }, onCancel: { Task { await self.release(query, id: id, waiter: waiter) } })
    }
    private func release(_ query: CriticRatingQuery, id: UUID, waiter: UUID) {
        guard var flight = pending[query], flight.id == id else { return }
        flight.waiters.remove(waiter)
        if flight.waiters.isEmpty { flight.task.cancel(); pending[query] = nil }
        else { pending[query] = flight }
    }
    private func resolve(_ query: CriticRatingQuery, now: Date, forceRefresh: Bool) async -> DatabaseMetadataResult {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(query) else { return .missing(.unavailable) }
        let file = directory.appendingPathComponent(IGDBCredentials.digest(String(decoding: data, as: UTF8.self)) + ".json")
        let bytes = try? InstallationFileSnapshot.read(at: file, maximumBytes: 262_144).data
        let decoded = bytes.flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
        let cached = decoded.flatMap { saved -> Cache? in
            guard saved.query == query else { return nil }
            if let preview = saved.preview {
                return preview.database == database && preview.isValid && database.platforms(for: query).contains(preview.platform) ? saved : nil
            }
            return saved.issue == .notFound || saved.issue == .ambiguous ? saved : nil
        }
        let ttl: TimeInterval = cached?.preview == nil ? 86400 : 7 * 86400
        if !forceRefresh, let cached, (0..<ttl).contains(now.timeIntervalSince(cached.fetchedAt)) {
            return .init(preview: cached.preview, issue: cached.issue, isStale: false)
        }
        do {
            let result = try await fetch(query)
            try Task.checkCancellation()
            if result.issue == nil || result.issue == .notFound || result.issue == .ambiguous {
                let saved = Cache(query: query, preview: result.preview, issue: result.issue, fetchedAt: now)
                if let data = try? encoder.encode(saved), data.count <= 262_144 {
                    do {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        try data.write(to: file, options: .atomic)
                    } catch { /* A valid preview does not depend on writing its cache. */ }
                }
                return result
            }
        } catch {
            if Task.isCancelled || error is CancellationError { return .missing(.cancelled) }
        }
        return .init(preview: cached?.preview, issue: .unavailable, isStale: cached?.preview != nil)
    }
    private func fetch(_ query: CriticRatingQuery) async throws -> DatabaseMetadataResult {
        let candidates: [DatabaseMetadataCandidate]
        switch database {
        case .launchBox:
            guard let url = LaunchBoxArt.searchURL(for: IGDBRatings.clean(query.name)) else { return .missing(.notFound) }
            let html = try await get(url)
            guard html.contains("__NUXT_DATA__") || html.contains("/games/details/") else { return .missing(.unavailable) }
            candidates = DatabaseMetadataParser.launchBoxCandidates(in: html, query: query)
        case .theGamesDB:
            var found: [DatabaseMetadataCandidate] = []
            for platform in database.platforms(for: query) {
                guard let url = DatabaseMetadataParser.gamesDBSearch(query: query, platform: platform) else { continue }
                let html = try await get(url)
                guard html.contains("game.php?id=") || html.contains("TheGamesDB") else { return .missing(.unavailable) }
                found = DatabaseMetadataParser.gamesDBCandidates(in: html, query: query, platform: platform)
                if !found.isEmpty { break }
            }
            candidates = found
        }
        guard candidates.count <= 1 else { return .missing(.ambiguous) }
        guard let match = candidates.first else { return .missing(.notFound) }
        let html = try await get(match.url)
        let result = try database == .launchBox
            ? DatabaseMetadataParser.launchBox(in: html, query: query, page: match.url)
            : DatabaseMetadataParser.theGamesDB(in: html, query: query, page: match.url)
        guard result.preview == nil || result.preview?.platform == match.platform else { return .missing(.unavailable) }
        return result
    }
    private func get(_ url: URL) async throws -> String {
        try Task.checkCancellation()
        guard Self.allowed(url), url.host == database.host else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.timeoutInterval = 12
        request.setValue(AppIdentity.userAgent(), forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode), response.url == url, data.count <= 2_097_152,
              let html = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        return html
    }
    private static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443 else { return false }
        if url.host == "gamesdb.launchbox-app.com" { return url.path.hasPrefix("/games/results/") || DatabaseMetadataParser.safe(url, database: .launchBox) }
        return url.host == "thegamesdb.net" && (url.path == "/search.php" || DatabaseMetadataParser.safe(url, database: .theGamesDB))
    }
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 20; config.timeoutIntervalForRequest = 12
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()
    private static func download(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, allowed(url) else { throw URLError(.badURL) }
        let (data, response) = try await BoundedDownload.data(for: request, session: session, limit: 2_097_152)
        guard let http = response as? HTTPURLResponse, http.url == url else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
