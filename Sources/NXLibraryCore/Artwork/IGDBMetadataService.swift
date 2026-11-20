import Foundation

/// On-demand source previews, separate from both the rating cache and personal metadata choices.
public actor IGDBMetadataService {
    public static let shared = IGDBMetadataService()
    private let directory: URL
    private let client: IGDBClient
    private struct Cache: Codable {
        let query: CriticRatingQuery
        let metadata: IGDBMetadata?
        let issue: IGDBMetadataIssue?
        let fetchedAt: Date
    }
    public init(directory: URL = AppData.supportRoot.appendingPathComponent("metadata/igdb"),
                transport: IGDBRatingService.Transport? = nil) {
        self.directory = directory
        client = transport.map { IGDBClient(transport: $0) } ?? .shared
    }
    public func load(_ query: CriticRatingQuery, credentials: IGDBCredentials, now: Date = Date()) async -> IGDBMetadataResult {
        guard !Task.isCancelled else { return .init(metadata: nil, issue: .cancelled, isStale: false) }
        guard !query.name.isEmpty, query.name.count <= 300 else { return .init(metadata: nil, issue: .notFound, isStale: false) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(query) else { return .init(metadata: nil, issue: .unavailable, isStale: false) }
        let key = IGDBCredentials.digest(credentials.clientID + String(decoding: data, as: UTF8.self))
        let file = directory.appendingPathComponent(key + ".json")
        let bytes = try? InstallationFileSnapshot.read(at: file, maximumBytes: 262_144).data
        let decoded = bytes.flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
        let cached = decoded.flatMap { saved -> Cache? in
            guard saved.query == query else { return nil }
            if let metadata = saved.metadata {
                return metadata.isValid && metadata.platform == query.platform ? saved : nil
            }
            return [.notFound, .ambiguous].contains(saved.issue) ? saved : nil
        }
        let ttl: TimeInterval = cached?.metadata == nil ? 86400 : 7 * 86400
        if let cached, (0..<ttl).contains(now.timeIntervalSince(cached.fetchedAt)) {
            return .init(metadata: cached.metadata, issue: cached.issue, isStale: false)
        }
        do {
            let result = try await fetch(query, credentials: credentials)
            try Task.checkCancellation()
            let saved = Cache(query: query, metadata: result.metadata, issue: result.issue, fetchedAt: now)
            if let data = try? encoder.encode(saved), data.count <= 262_144 {
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try data.write(to: file, options: .atomic)
                } catch { /* An unavailable cache never discards a valid preview. */ }
            }
            return result
        } catch {
            if Task.isCancelled || error is CancellationError { return .init(metadata: nil, issue: .cancelled, isStale: false) }
            return .init(metadata: cached?.metadata, issue: .unavailable, isStale: cached?.metadata != nil)
        }
    }
    private func fetch(_ query: CriticRatingQuery, credentials: IGDBCredentials) async throws -> IGDBMetadataResult {
        if let appID = query.steamAppID {
            let fields = IGDBMetadataParser.fields.split(separator: ",").map { "game." + $0 }.joined(separator: ",")
            let body = "fields uid,external_game_source.name,\(fields); where uid = \"\(appID)\" & external_game_source.name = \"Steam\"; limit 10;"
            let data = try await client.request("external_games", body: body, credentials: credentials)
            let result = try IGDBMetadataParser.steamResult(in: data, query: query)
            if result.issue != .notFound { return result }
        }
        let body = IGDBRatings.body(for: query, fields: IGDBMetadataParser.fields)
        return try IGDBMetadataParser.result(in: await client.request("games", body: body, credentials: credentials), query: query)
    }
}
