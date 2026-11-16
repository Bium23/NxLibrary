import Foundation

/// User-owned IGDB credentials only. Tokens live in memory; network errors never include server bodies.
public actor IGDBRatingService {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public static let shared = IGDBRatingService()
    private let directory: URL
    private let transport: Transport
    private struct Token { let owner: String; let value: String; let expires: Date }
    private struct Cache: Codable { let query: CriticRatingQuery; let rating: CriticRating?; let fetchedAt: Date }
    private struct Flight { let id: UUID; let task: Task<CriticRatingResult, Never>; var waiters: Set<UUID> }
    private var pending: [String: Flight] = [:]
    private var workTail: Task<Void, Never>?
    private var token: Token?
    private var lastRequest = Date.distantPast
    private var backoff: [String: Date] = [:]

    public init(directory: URL = AppData.supportRoot.appendingPathComponent("ratings/igdb"),
                transport: @escaping Transport = { try await IGDBRatingService.download($0) }) {
        self.directory = directory; self.transport = transport
    }
    public func invalidate() {
        for flight in pending.values { flight.task.cancel() }
        pending.removeAll(); token = nil; backoff.removeAll()
    }
    public func check(_ credentials: IGDBCredentials) async throws {
        let prior = workTail
        let task = Task {
            await prior?.value
            try Task.checkCancellation()
            self.token = nil
            let data = try await self.api("games", body: "fields id; limit 1;", credentials: credentials)
            guard (try? JSONSerialization.jsonObject(with: data)) is [[String: Any]] else { throw IGDBError.invalidResponse }
            self.backoff[credentials.fingerprint] = nil
        }
        workTail = Task { _ = try? await task.value }
        try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }
    public func load(_ query: CriticRatingQuery, credentials: IGDBCredentials, now: Date = Date()) async -> CriticRatingResult {
        let empty = CriticRatingResult(rating: nil, fetchedAt: nil, isStale: false)
        guard !Task.isCancelled, !query.name.isEmpty, query.name.count <= 300 else { return empty }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let encoded = try? encoder.encode(query) else { return empty }
        let key = IGDBCredentials.digest(credentials.fingerprint + String(decoding: encoded, as: UTF8.self))
        let cacheKey = IGDBCredentials.digest(credentials.clientID + String(decoding: encoded, as: UTF8.self))
        let waiter = UUID()
        var flight: Flight
        if let existing = pending[key] { flight = existing; flight.waiters.insert(waiter) }
        else {
            guard pending.count < 4 else { return empty }
            let prior = workTail
            let task = Task {
                await prior?.value
                guard !Task.isCancelled else { return empty }
                return await self.resolve(query, credentials: credentials, key: cacheKey, now: now)
            }
            workTail = Task { _ = await task.value }
            flight = Flight(id: UUID(), task: task, waiters: [waiter])
        }
        pending[key] = flight
        let id = flight.id, task = flight.task
        return await withTaskCancellationHandler(operation: {
            defer { release(key, id: id, waiter: waiter) }
            let result = await task.value
            return Task.isCancelled ? empty : result
        }, onCancel: { Task { await self.release(key, id: id, waiter: waiter) } })
    }
    private func release(_ key: String, id: UUID, waiter: UUID) {
        guard var flight = pending[key], flight.id == id else { return }
        flight.waiters.remove(waiter)
        if flight.waiters.isEmpty { flight.task.cancel(); pending[key] = nil }
        else { pending[key] = flight }
    }
    private func resolve(_ query: CriticRatingQuery, credentials: IGDBCredentials, key: String, now: Date) async -> CriticRatingResult {
        let file = directory.appendingPathComponent(key + ".json")
        let cached = (try? InstallationFileSnapshot.read(at: file, maximumBytes: 65_536).data)
            .flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
            .flatMap { $0.query == query && ($0.rating == nil || ($0.rating?.source == .igdb && $0.rating?.isValid == true)) ? $0 : nil }
        func result(_ cache: Cache?, stale: Bool) -> CriticRatingResult {
            CriticRatingResult(rating: cache?.rating, fetchedAt: cache?.fetchedAt, isStale: stale && cache != nil)
        }
        let ttl: TimeInterval = cached?.rating == nil ? 86400 : 7 * 86400
        if let cached, (0..<ttl).contains(now.timeIntervalSince(cached.fetchedAt)) { return result(cached, stale: false) }
        if let pause = backoff[credentials.fingerprint], pause > Date() { return result(cached, stale: true) }
        do {
            var rating: CriticRating?
            if let appID = query.steamAppID {
                let fields = IGDBRatings.fields.split(separator: ",").map { "game." + $0 }.joined(separator: ",")
                let body = "fields uid,external_game_source.name,\(fields); where uid = \"\(appID)\" & external_game_source.name = \"Steam\"; limit 10;"
                let data = try await api("external_games", body: body, credentials: credentials)
                rating = try IGDBRatings.steamRating(in: data, appID: appID)
            }
            if rating == nil {
                let data = try await api("games", body: IGDBRatings.body(for: query), credentials: credentials)
                rating = try IGDBRatings.rating(in: data, query: query)
            }
            try Task.checkCancellation()
            let value = Cache(query: query, rating: rating, fetchedAt: now)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(value).write(to: file, options: .atomic)
            } catch { /* A valid rating still works for this appearance if cache writing is unavailable. */ }
            return result(value, stale: false)
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { backoff[credentials.fingerprint] = Date().addingTimeInterval(60) }
            return result(cached, stale: true)
        }
    }
    private func accessToken(_ credentials: IGDBCredentials) async throws -> String {
        if let token, token.owner == credentials.fingerprint, token.expires > Date() { return token.value }
        var form = URLComponents()
        form.queryItems = [.init(name: "client_id", value: credentials.clientID), .init(name: "client_secret", value: credentials.clientSecret),
                           .init(name: "grant_type", value: "client_credentials")]
        var request = URLRequest(url: URL(string: "https://id.twitch.tv/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await send(request)
        guard response.statusCode == 200 else {
            throw [400, 401, 403].contains(response.statusCode) ? IGDBError.rejected : IGDBError.unreachable
        }
        struct Wire: Decodable { let access_token: String; let expires_in: Double; let token_type: String }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data), wire.token_type.lowercased() == "bearer",
              wire.expires_in.isFinite, wire.expires_in > 60, wire.access_token.count <= 2048,
              !wire.access_token.isEmpty, wire.access_token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        else { throw IGDBError.invalidResponse }
        try Task.checkCancellation()
        token = Token(owner: credentials.fingerprint, value: wire.access_token,
                      expires: Date().addingTimeInterval(min(wire.expires_in, 31_622_400) - 60))
        return wire.access_token
    }
    private func api(_ endpoint: String, body: String, credentials: IGDBCredentials) async throws -> Data {
        for attempt in 0...1 {
            let access = try await accessToken(credentials)
            var request = URLRequest(url: URL(string: "https://api.igdb.com/v4/\(endpoint)")!)
            request.httpMethod = "POST"; request.httpBody = Data(body.utf8)
            request.setValue(credentials.clientID, forHTTPHeaderField: "Client-ID")
            request.setValue("Bearer " + access, forHTTPHeaderField: "Authorization")
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await send(request)
            if response.statusCode == 401, attempt == 0 { token = nil; continue }
            guard (200..<300).contains(response.statusCode) else {
                if response.statusCode == 429 { throw IGDBError.rateLimited }
                throw [401,403].contains(response.statusCode) ? IGDBError.rejected : IGDBError.unreachable
            }
            return data
        }
        throw IGDBError.rejected
    }
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let delay = 0.26 - Date().timeIntervalSince(lastRequest)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        try Task.checkCancellation()
        lastRequest = Date()
        do {
            let result = try await transport(request)
            try Task.checkCancellation()
            guard result.0.count <= 2_097_152, result.1.url == request.url else { throw IGDBError.invalidResponse }
            return result
        } catch is CancellationError { throw CancellationError() }
        catch let error as IGDBError { throw error }
        catch { throw IGDBError.unreachable }
    }
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 20; config.timeoutIntervalForRequest = 12
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()
    public static func download(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.query == nil, request.httpMethod == "POST",
              (url.host == "id.twitch.tv" && url.path == "/oauth2/token") ||
                (url.host == "api.igdb.com" && ["/v4/games", "/v4/external_games"].contains(url.path)) else { throw IGDBError.unreachable }
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("NXLibrary/0.2 (https://github.com/Bium23/NxLibrary)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url == url, response.expectedContentLength <= 2_097_152 else { throw IGDBError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_097_152 else { throw IGDBError.invalidResponse }
            data.append(byte)
        }
        return (data, http)
    }
}
