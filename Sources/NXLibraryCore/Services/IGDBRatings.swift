import Foundation

/// Only IGDB's external-critic aggregate, with an exact identity. Not rating/total_rating.
public enum IGDBRatings {
    static let fields = "id,name,alternative_names.name,platforms,aggregated_rating,aggregated_rating_count,url"
    static func clean(_ name: String) -> String {
        ["™", "®", "©"].reduce(name) { $0.replacingOccurrences(of: $1, with: "") }
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func normalized(_ name: String) -> String {
        String(clean(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
    static func body(for query: CriticRatingQuery) -> String {
        let escaped = clean(query.name).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "search \"\(escaped)\"; fields \(fields); limit 20;"
    }
    static func safeGameURL(_ url: URL) -> URL? {
        guard url.scheme == "https", ["www.igdb.com", "igdb.com"].contains(url.host ?? ""),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              url.path.hasPrefix("/games/") else { return nil }
        return url
    }
    public static func rating(in data: Data, query: CriticRatingQuery) throws -> CriticRating? {
        let games = try decode(data)
        let target = normalized(query.name)
        let matching = games.filter { game in
            ([game.name] + (game.alternative_names ?? []).map(\.name)).contains { normalized($0) == target }
                && (game.platforms ?? []).contains(query.platform.igdbID)
        }
        guard matching.count == 1, let game = matching.first else { return nil }
        return game.rating
    }
    struct Game: Decodable {
        struct Name: Decodable { let name: String }
        let id: Int
        let name: String
        let alternative_names: [Name]?
        let platforms: [Int]?
        let aggregated_rating: Double?
        let aggregated_rating_count: Int?
        let url: URL?
        var rating: CriticRating? {
            guard id > 0, let score = aggregated_rating, score.isFinite, (0...100).contains(score),
                  let count = aggregated_rating_count, count > 0, let url, let safe = safeGameURL(url) else { return nil }
            return CriticRating(score: score, source: .igdb, igdbID: id, igdbURL: safe, reviewCount: count)
        }
    }
    static func decode(_ data: Data) throws -> [Game] {
        guard data.count <= 2_097_152 else { throw IGDBError.invalidResponse }
        do { return try JSONDecoder().decode([Game].self, from: data) } catch { throw IGDBError.invalidResponse }
    }
    static func steamRating(in data: Data, appID: UInt32) throws -> CriticRating? {
        struct External: Decodable {
            struct Source: Decodable { let name: String }
            let uid: String
            let external_game_source: Source
            let game: Game
        }
        guard data.count <= 2_097_152 else { throw IGDBError.invalidResponse }
        let entries: [External]
        do { entries = try JSONDecoder().decode([External].self, from: data) } catch { throw IGDBError.invalidResponse }
        let matching = entries.filter { $0.uid == String(appID) && $0.external_game_source.name.lowercased() == "steam" }
        let games = Dictionary(grouping: matching, by: { $0.game.id })
        guard games.count == 1, let game = matching.first?.game else { return nil }
        // The exact external ID establishes identity even when a Mac port is absent from IGDB's platform list.
        // Its returned score remains explicitly an overall game aggregate, not a Mac-specific score.
        return game.rating
    }
}
