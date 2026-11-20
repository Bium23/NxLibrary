import Foundation

/// The two public databases offered alongside store-specific metadata. A shop ID is not required.
public enum MetadataDatabase: String, CaseIterable, Codable, Sendable {
    case launchBox, theGamesDB
    public var name: String { self == .launchBox ? "LaunchBox" : "TheGamesDB" }
    var host: String { self == .launchBox ? "gamesdb.launchbox-app.com" : "thegamesdb.net" }
    func platforms(for query: CriticRatingQuery) -> [String] {
        switch query.platform {
        case .mac: return self == .launchBox ? ["Apple Mac OS", "Windows"] : ["Mac OS", "PC"]
        case .switch: return ["Nintendo Switch"]
        case .switch2: return ["Nintendo Switch 2"]
        }
    }
}

public struct DatabaseMetadataPreview: Codable, Equatable, Sendable {
    public let database: MetadataDatabase
    public let name: String
    public let platform: String
    public let page: URL
    public let values: [MetadataField: String]
    public func option(for field: MetadataField) -> MetadataOption? {
        values[field].map { MetadataOption(field: field, source: "\(database.name) · \(platform)", value: $0) }
    }
    var isValid: Bool {
        !name.isEmpty && name.count <= 300 && !platform.isEmpty
            && DatabaseMetadataParser.safe(page, database: database)
            && values.values.allSatisfy { !$0.isEmpty && $0.count <= 32_768 }
    }
}

public enum DatabaseMetadataIssue: String, Codable, Equatable, Sendable { case notFound, ambiguous, unavailable, cancelled }
public struct DatabaseMetadataResult: Equatable, Sendable {
    public let preview: DatabaseMetadataPreview?
    public let issue: DatabaseMetadataIssue?
    public let isStale: Bool
    static func missing(_ issue: DatabaseMetadataIssue) -> Self { .init(preview: nil, issue: issue, isStale: false) }
}

public struct DatabaseMetadataCandidate: Hashable, Sendable {
    public let url: URL
    public let title: String
    public let platform: String
}

/// Bounded, string-only parsing of the same public pages used by the existing artwork flows.
public enum DatabaseMetadataParser {
    static func safe(_ url: URL, database: MetadataDatabase) -> Bool {
        guard url.scheme == "https", url.host == database.host, url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.fragment == nil else { return false }
        if database == .launchBox {
            return url.path.range(of: #"^/games/details/[0-9]+-[A-Za-z0-9-]*$"#, options: .regularExpression) != nil
                && (Int(url.lastPathComponent.prefix { $0.isNumber }) ?? 0) > 0 && url.query == nil
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return url.path == "/game.php" && items.count == 1 && items[0].name == "id" && (Int(items[0].value ?? "") ?? 0) > 0
    }
    static func capture(_ pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }
    static func text(_ html: String) -> String { HTMLPlainText.text(fromHTML: html) }
    static func sameName(_ name: String, query: CriticRatingQuery) -> Bool { IGDBRatings.normalized(name) == IGDBRatings.normalized(query.name) }

    public static func launchBoxCandidates(in html: String, query: CriticRatingQuery) -> [DatabaseMetadataCandidate] {
        let named = LaunchBoxArt.results(in: html).filter { sameName($0.title, query: query) }
        for platform in MetadataDatabase.launchBox.platforms(for: query) {
            let matches = named.filter { $0.platform == platform }.compactMap { result -> DatabaseMetadataCandidate? in
                guard let url = URL(string: result.path, relativeTo: LaunchBoxArt.site)?.absoluteURL, safe(url, database: .launchBox) else { return nil }
                return .init(url: url, title: result.title, platform: platform)
            }
            if !matches.isEmpty { return Array(Set(matches)).sorted { $0.url.absoluteString < $1.url.absoluteString } }
        }
        return []
    }

    public static func launchBox(in html: String, query: CriticRatingQuery, page: URL) throws -> DatabaseMetadataResult {
        guard safe(page, database: .launchBox), html.utf8.count <= 2_097_152,
              let json = capture(#"<script[^>]*id=["']__NUXT_DATA__["'][^>]*>(.*?)</script>"#, in: html),
              let graph = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any] else { return .missing(.unavailable) }
        func value(_ object: [String: Any], _ key: String) -> Any? {
            guard let index = object[key] as? Int, graph.indices.contains(index) else { return nil }
            return graph[index]
        }
        func names(_ object: [String: Any], _ key: String) -> String {
            let indices = value(object, key) as? [Int] ?? []
            return indices.compactMap { index -> String? in
                guard graph.indices.contains(index), let named = graph[index] as? [String: Any] else { return nil }
                return value(named, "name") as? String
            }.joined(separator: ", ")
        }
        let id = Int(page.lastPathComponent.prefix { $0.isNumber })
        let objects = graph.compactMap { $0 as? [String: Any] }.filter { (value($0, "gameKey") as? Int) == id && $0["overview"] != nil }
        guard objects.count == 1, let object = objects.first,
              let name = value(object, "name") as? String,
              let platformObject = value(object, "platform") as? [String: Any],
              let platform = value(platformObject, "name") as? String else { return .missing(.unavailable) }
        guard sameName(name, query: query), MetadataDatabase.launchBox.platforms(for: query).contains(platform) else { return .missing(.notFound) }
        return preview(database: .launchBox, name: name, platform: platform, page: page, query: query, values: [
            .description: value(object, "overview") as? String ?? "",
            .genres: names(object, "gameGenres"), .developer: names(object, "gameDevelopers"),
            .publisher: names(object, "gamePublishers"), .releaseDate: value(object, "releaseDate") as? String ?? ""
        ])
    }

    static let gamesDBPlatformIDs = ["Mac OS": "37", "PC": "1", "Nintendo Switch": "4971", "Nintendo Switch 2": "5021"]
    static func gamesDBSearch(query: CriticRatingQuery, platform: String) -> URL? {
        guard let id = gamesDBPlatformIDs[platform] else { return nil }
        var url = URLComponents(string: "https://thegamesdb.net/search.php")!
        url.queryItems = [.init(name: "name", value: IGDBRatings.clean(query.name)), .init(name: "platform_id[]", value: id)]
        return url.url
    }
    static func gamesDBCandidates(in html: String, query: CriticRatingQuery, platform: String) -> [DatabaseMetadataCandidate] {
        var found = Set<DatabaseMetadataCandidate>()
        for card in html.components(separatedBy: "game.php?id=").dropFirst() {
            guard let id = Int(card.prefix { $0.isNumber }), id > 0,
                  let footer = card.range(of: "card-footer"),
                  let title = capture(#"<p\b[^>]*>(.*?)</p>"#, in: String(card[footer.upperBound...])),
                  let from = capture(#"<p[^>]*class=["'][^"']*text-muted[^"']*["'][^>]*>(.*?)</p>"#, in: card),
                  text(from) == platform, sameName(text(title), query: query) else { continue }
            found.insert(.init(url: TheGamesDBArt.gameURL(id: id), title: text(title), platform: platform))
        }
        return found.sorted { $0.url.absoluteString < $1.url.absoluteString }
    }
    public static func theGamesDB(in html: String, query: CriticRatingQuery, page: URL) -> DatabaseMetadataResult {
        guard safe(page, database: .theGamesDB), html.utf8.count <= 2_097_152,
              let heading = capture(#"<h1\b[^>]*>(.*?)</h1>"#, in: html),
              let platformHTML = capture(#"<p\b[^>]*>\s*Platform:\s*(.*?)</p>"#, in: html) else { return .missing(.unavailable) }
        let name = text(heading), platform = text(platformHTML)
        guard sameName(name, query: query), MetadataDatabase.theGamesDB.platforms(for: query).contains(platform) else { return .missing(.notFound) }
        func field(_ label: String) -> String {
            capture(#"<p\b[^>]*>\s*"# + NSRegularExpression.escapedPattern(for: label) + #"\s*(.*?)</p>"#, in: html).map(text) ?? ""
        }
        return preview(database: .theGamesDB, name: name, platform: platform, page: page, query: query, values: [
            .description: capture(#"<p[^>]*class=["'][^"']*game-overview[^"']*["'][^>]*>(.*?)</p>"#, in: html) ?? "",
            .developer: field("Developer(s):"), .publisher: field("Publishers(s):"),
            .genres: field("Genre(s):").components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", "),
            .releaseDate: field("ReleaseDate:")
        ])
    }
    private static func preview(database: MetadataDatabase, name: String, platform: String, page: URL,
                                query: CriticRatingQuery, values: [MetadataField: String]) -> DatabaseMetadataResult {
        var fields = values.mapValues(text).filter { !$0.value.isEmpty && $0.value.count <= 32_768 }
        if let date = fields[.releaseDate] {
            let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = TimeZone(secondsFromGMT: 0)
            format.dateFormat = "yyyy-MM-dd"; format.isLenient = false
            if date.count != 10 || format.date(from: date).map({ format.string(from: $0) == date }) != true { fields[.releaseDate] = nil }
        }
        if query.platform == .mac && ["PC", "Windows"].contains(platform) { fields[.releaseDate] = nil }
        let result = DatabaseMetadataPreview(database: database, name: name, platform: platform, page: page, values: fields)
        return result.isValid ? .init(preview: result, issue: nil, isStale: false) : .missing(.unavailable)
    }
}
