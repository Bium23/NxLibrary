import Foundation

/// User-owned IGDB credentials only. Tokens live in memory; network errors never include server bodies.
public actor IGDBRatingService {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public static let shared = IGDBRatingService()
    private let directory: URL
    private let client: IGDBClient
    private struct Cache: Codable {
        let query: CriticRatingQuery
        let rating: CriticRating?
        let fetchedAt: Date
        let resolverVersion: Int?
    }
    private struct Flight { let id: UUID; let task: Task<CriticRatingResult, Never>; var waiters: Set<UUID> }
    private var pending: [String: Flight] = [:]
    private var workTail: Task<Void, Never>?
    private var backoff: [String: Date] = [:]

    public init(directory: URL = AppData.supportRoot.appendingPathComponent("ratings/igdb"),
                transport: Transport? = nil) {
        self.directory = directory
        self.client = transport.map { IGDBClient(transport: $0) } ?? .shared
    }
    public func invalidate() async {
        for flight in pending.values { flight.task.cancel() }
        pending.removeAll(); backoff.removeAll()
        await client.resetToken()
    }
    public func check(_ credentials: IGDBCredentials) async throws {
        let prior = workTail
        let task = Task {
            await prior?.value
            try Task.checkCancellation()
            let data = try await self.api("games", body: "fields id; limit 1;", credentials: credentials, renewToken: true)
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
        let bytes = try? InstallationFileSnapshot.read(at: file, maximumBytes: 65_536).data
        let decoded = bytes.flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
        let cached: Cache? = {
            guard let saved = decoded, saved.query == query else { return nil }
            if let rating = saved.rating {
                return rating.source == .igdb && rating.isValid ? saved : nil
            }
            return saved.resolverVersion == 2 ? saved : nil
        }()
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
            let value = Cache(query: query, rating: rating, fetchedAt: now, resolverVersion: 2)
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
    private func api(_ endpoint: String, body: String, credentials: IGDBCredentials, renewToken: Bool = false) async throws -> Data {
        try await client.request(endpoint, body: body, credentials: credentials, renewToken: renewToken)
    }
}
