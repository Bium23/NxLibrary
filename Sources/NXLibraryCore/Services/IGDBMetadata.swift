import Foundation

/// A source preview, never a personalization. Values are applied only through the existing picker.
public struct IGDBMetadata: Codable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let platform: CriticRatingQuery.Platform
    public let url: URL
    public let values: [MetadataField: String]

    public func option(for field: MetadataField) -> MetadataOption? {
        values[field].map { MetadataOption(field: field, source: "IGDB", value: $0) }
    }
    var isValid: Bool {
        id > 0 && !name.isEmpty && name.count <= 300 && IGDBRatings.safeGameURL(url) != nil
            && values.values.allSatisfy { !$0.isEmpty && $0.count <= 32_768 }
    }
}

public enum IGDBMetadataIssue: String, Codable, Equatable, Sendable {
    case notFound, ambiguous, unavailable, cancelled
}

public struct IGDBMetadataResult: Equatable, Sendable {
    public let metadata: IGDBMetadata?
    public let issue: IGDBMetadataIssue?
    public let isStale: Bool
}

public enum IGDBMetadataParser {
    static let fields = "id,name,alternative_names.name,platforms,url,summary,genres.name,involved_companies.company.name,involved_companies.developer,involved_companies.publisher,release_dates.platform,release_dates.date,release_dates.date_format.format"

    private struct Game: Decodable {
        struct Name: Decodable { let name: String }
        struct Company: Decodable { let company: Name?; let developer: Bool?; let publisher: Bool? }
        struct Release: Decodable {
            struct Format: Decodable { let format: String }
            let platform: Int?
            let date: Double?
            let date_format: Format?
        }
        let id: Int
        let name: String
        let alternative_names: [Name]?
        let platforms: [Int]?
        let url: URL?
        let summary: String?
        let genres: [Name]?
        let involved_companies: [Company]?
        let release_dates: [Release]?

        func preview(for query: CriticRatingQuery) -> IGDBMetadata? {
            guard id > 0, let url, let safe = IGDBRatings.safeGameURL(url) else { return nil }
            var values: [MetadataField: String] = [:]
            func add(_ field: MetadataField, _ value: String?) {
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty, value.count <= 32_768 else { return }
                values[field] = value
            }
            func names(_ list: [String]) -> String {
                var seen = Set<String>()
                return list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.joined(separator: ", ")
            }
            add(.description, summary)
            add(.genres, names((genres ?? []).map(\.name)))
            add(.developer, names((involved_companies ?? []).filter { $0.developer == true }.compactMap { $0.company?.name }))
            add(.publisher, names((involved_companies ?? []).filter { $0.publisher == true }.compactMap { $0.company?.name }))
            let dates = (release_dates ?? []).compactMap { release -> Double? in
                guard release.platform == query.platform.igdbID, release.date_format?.format == "YYYYMMDD",
                      let date = release.date, date.isFinite, (-2_208_988_800...7_258_118_400).contains(date) else { return nil }
                return date
            }
            if let date = dates.min() {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]; formatter.timeZone = TimeZone(secondsFromGMT: 0)
                add(.releaseDate, formatter.string(from: Date(timeIntervalSince1970: date)))
            }
            let metadata = IGDBMetadata(id: id, name: name, platform: query.platform, url: safe, values: values)
            return metadata.isValid ? metadata : nil
        }
    }

    public static func result(in data: Data, query: CriticRatingQuery) throws -> IGDBMetadataResult {
        let games: [Game] = try decode(data)
        let matching = games.filter {
            IGDBRatings.matches(name: $0.name, aliases: ($0.alternative_names ?? []).map(\.name), platforms: $0.platforms ?? [], query: query)
        }
        return result(matching, query: query)
    }

    public static func steamResult(in data: Data, query: CriticRatingQuery) throws -> IGDBMetadataResult {
        struct External: Decodable {
            struct Source: Decodable { let name: String }
            let uid: String
            let external_game_source: Source
            let game: Game
        }
        guard let appID = query.steamAppID else { return result([], query: query) }
        let entries: [External] = try decode(data)
        let matching = entries.filter { $0.uid == String(appID) && $0.external_game_source.name.lowercased() == "steam" }
        let unique = Dictionary(grouping: matching.map(\.game), by: \.id).compactMap { $0.value.first }
        return result(unique, query: query)
    }

    private static func result(_ games: [Game], query: CriticRatingQuery) -> IGDBMetadataResult {
        guard games.count <= 1 else { return .init(metadata: nil, issue: .ambiguous, isStale: false) }
        guard let metadata = games.first?.preview(for: query) else { return .init(metadata: nil, issue: .notFound, isStale: false) }
        return .init(metadata: metadata, issue: nil, isStale: false)
    }
    private static func decode<T: Decodable>(_ data: Data) throws -> T {
        guard data.count <= 2_097_152 else { throw IGDBError.invalidResponse }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw IGDBError.invalidResponse }
    }
}
