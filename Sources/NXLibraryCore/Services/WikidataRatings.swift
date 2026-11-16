import Foundation

/// Narrow Wikidata contract: exact video-game identity and referenced /100 critic aggregates.
/// Source/metric IDs come from the inspected P444/P447/P459 statements, not label guesses.
public enum WikidataRatings {
    static func isItemID(_ value: String) -> Bool {
        value.first == "Q" && value.count > 1 && value.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
    }
    private static func normalized(_ value: String) -> String {
        String(value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
    public static func searchURL(name: String) -> URL? {
        guard !name.isEmpty, name.count <= 300 else { return nil }
        return url(["action": "wbsearchentities", "search": name, "language": "en", "type": "item", "limit": "5"])
    }
    public static func entitiesURL(ids: [String]) -> URL? {
        guard !ids.isEmpty, ids.count <= 5, ids.allSatisfy(isItemID) else { return nil }
        return url(["action": "wbgetentities", "ids": ids.joined(separator: "|"), "props": "claims"])
    }
    private static func url(_ values: [String: String]) -> URL? {
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = (values.merging(["format": "json", "maxlag": "5"], uniquingKeysWith: { _, b in b }))
            .sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        return components.url
    }
    public static func ids(in data: Data, name: String) throws -> [String] {
        let root = try object(data)
        guard let search = root["search"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        let target = normalized(name)
        guard !target.isEmpty else { return [] }
        return Array(Set(search.compactMap { item -> String? in
            guard let id = item["id"] as? String, isItemID(id) else { return nil }
            let names = [item["label"] as? String].compactMap { $0 } + (item["aliases"] as? [String] ?? [])
            return names.contains { normalized($0) == target } ? id : nil
        })).sorted()
    }
    public static func rating(in data: Data, ids: [String], query: CriticRatingQuery) throws -> CriticRating? {
        let root = try object(data)
        guard let entities = root["entities"] as? [String: [String: Any]],
              ids.allSatisfy({ entities[$0] != nil }) else { throw URLError(.cannotParseResponse) }
        let matched = ids.filter { id in
            guard let claims = entities[id]?["claims"] as? [String: [[String: Any]]],
                  claimItems(claims["P31"] ?? []).contains("Q7889") else { return false }
            let steam = (claims["P1733"] ?? []).filter { ($0["rank"] as? String) != "deprecated" }
                .compactMap { ($0["mainsnak"] as? [String: Any]).flatMap(value) as? String }
            if let expected = query.steamAppID, !steam.isEmpty { return steam.contains(String(expected)) }
            return true
        }
        guard matched.count == 1, let id = matched.first,
              let claims = entities[id]?["claims"] as? [String: [[String: Any]]] else { return nil }
        let ratings = (claims["P444"] ?? []).compactMap { parse($0, entityID: id, platform: query.platform.wikidataID) }
        return ratings.sorted { a, b in
            if a.platforms.isEmpty != b.platforms.isEmpty { return !a.platforms.isEmpty }
            if a.source.priority != b.source.priority { return a.source.priority < b.source.priority }
            if a.scoreDate != b.scoreDate { return (a.scoreDate ?? "") > (b.scoreDate ?? "") }
            return a.statementID < b.statementID
        }.first
    }
    private static func parse(_ claim: [String: Any], entityID: String, platform: String) -> CriticRating? {
        guard claim["rank"] as? String != "deprecated",
              let raw = (claim["mainsnak"] as? [String: Any]).flatMap(value) as? String,
              let statement = claim["id"] as? String, statement.hasPrefix(entityID + "$"),
              let quals = claim["qualifiers"] as? [String: [[String: Any]]] else { return nil }
        let issuerSnaks = quals["P447"] ?? []
        let issuers = issuerSnaks.compactMap(item)
        guard issuerSnaks.count == 1, issuers.count == 1 else { return nil }
        let source: CriticRating.Source
        let metric: String
        switch issuers[0] {
        case "Q21039459": source = .openCritic; metric = "Q114712322"
        case "Q150248": source = .metacritic; metric = "Q106515043"
        case "Q131917281": source = .criticDB; metric = "Q132178503"
        default: return nil
        }
        let methods = (quals["P459"] ?? []).compactMap(item)
        guard methods.count == (quals["P459"] ?? []).count else { return nil }
        guard methods == [metric] || (methods.isEmpty && source == .metacritic) else { return nil }
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let score = Double(parts[0]), Double(parts[1]) == 100,
              score.isFinite, (0...100).contains(score) else { return nil }
        let platforms = (quals["P400"] ?? []).compactMap(item)
        guard platforms.count == (quals["P400"] ?? []).count else { return nil }
        guard platforms.isEmpty || platforms.contains(platform) else { return nil }
        let refs = (claim["references"] as? [[String: Any]] ?? []).compactMap { $0["snaks"] as? [String: [[String: Any]]] }
        let urls = refs.flatMap { $0["P854"] ?? [] }.compactMap { value($0) as? String }.compactMap(URL.init(string:))
            .filter { $0.scheme == "https" && $0.host != nil && $0.user == nil && $0.password == nil }
        let items = refs.flatMap { $0["P248"] ?? [] }.compactMap(item)
        guard !urls.isEmpty || !items.isEmpty else { return nil }
        let date = (quals["P585"] ?? []).compactMap { value($0) as? [String: Any] }.compactMap { $0["time"] as? String }.sorted().last
        return CriticRating(score: score, source: source, entityID: entityID, statementID: statement,
                            referenceURLs: urls, referenceItems: items, scoreDate: date, platforms: platforms)
    }
    private static func value(_ snak: [String: Any]) -> Any? { (snak["datavalue"] as? [String: Any])?["value"] }
    private static func item(_ snak: [String: Any]) -> String? {
        guard let id = (value(snak) as? [String: Any])?["id"] as? String, isItemID(id) else { return nil }
        return id
    }
    private static func claimItems(_ claims: [[String: Any]]) -> [String] {
        claims.filter { $0["rank"] as? String != "deprecated" }.compactMap { ($0["mainsnak"] as? [String: Any]).flatMap(item) }
    }
    private static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= 4_194_304, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["error"] == nil else { throw URLError(.cannotParseResponse) }
        return root
    }
}
