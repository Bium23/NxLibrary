import Foundation

/// Public lookup identity only. Never sends catalog paths, account IDs or play history.
public struct CriticRatingQuery: Hashable, Codable, Sendable {
    public enum Platform: String, Codable, Sendable {
        case mac, `switch`, switch2
        var wikidataID: String {
            switch self {
            case .mac: return "Q14116"
            case .switch: return "Q19610114"
            case .switch2: return "Q122761124"
            }
        }
        var igdbID: Int {
            switch self {
            case .mac: return 14
            case .switch: return 130
            case .switch2: return 508
            }
        }
    }
    public let name: String
    public let platform: Platform
    public let steamAppID: UInt32?

    public init(name: String, platform: Platform, steamAppID: UInt32? = nil) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.platform = platform
        self.steamAppID = steamAppID
    }
}

/// One attributed average; community scores are explicit fallbacks, never mixed with critics.
public struct CriticRating: Equatable, Codable, Sendable {
    public enum Audience: String, Codable, Sendable { case critics, users }
    public enum Source: String, Codable, Sendable {
        case openCritic, metacritic, criticDB, igdb
        public var name: String {
            switch self {
            case .openCritic: return "OpenCritic"
            case .metacritic: return "Metacritic"
            case .criticDB: return "CriticDB"
            case .igdb: return "IGDB"
            }
        }
        var priority: Int {
            switch self { case .igdb: return -1; case .openCritic: return 0; case .metacritic: return 1; case .criticDB: return 2 }
        }
    }
    public let score: Double
    public let source: Source
    public let entityID: String?
    public let statementID: String?
    public let referenceURLs: [URL]
    public let referenceItems: [String]
    /// Wikidata's point-in-time, not the date the app fetched this value.
    public let scoreDate: String?
    /// Empty means platform unspecified; never inferred from the requesting game's platform.
    public let platforms: [String]
    public let igdbID: Int?
    public let igdbURL: URL?
    public let reviewCount: Int?
    /// Nil in older caches means critics; users are always explicitly identified.
    public let audience: Audience?

    public init(score: Double, source: Source, entityID: String? = nil, statementID: String? = nil,
                referenceURLs: [URL] = [], referenceItems: [String] = [], scoreDate: String? = nil,
                platforms: [String] = [], igdbID: Int? = nil, igdbURL: URL? = nil, reviewCount: Int? = nil,
                audience: Audience = .critics) {
        self.score = score; self.source = source; self.entityID = entityID; self.statementID = statementID
        self.referenceURLs = referenceURLs; self.referenceItems = referenceItems; self.scoreDate = scoreDate
        self.platforms = platforms; self.igdbID = igdbID; self.igdbURL = igdbURL; self.reviewCount = reviewCount
        self.audience = audience
    }

    public var isCommunity: Bool { audience == .users }
    public var labelKey: String { isCommunity ? "User score" : "Critic score" }
    public func attribution(context: AppLocale? = nil) -> String {
        if isCommunity { return L10n.text("Users · IGDB", context: context) }
        return source == .igdb ? "IGDB" : "\(source.name) · Wikidata"
    }
    public var starFills: [Double] { (0..<5).map { max(0, min(1, score / 20 - Double($0))) } }
    public func number(locale: Locale = L10n.context.formatLocale) -> String {
        score.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + "/100"
    }
    public var sourceURL: URL {
        if source == .igdb { return igdbURL ?? URL(string: "https://www.igdb.com")! }
        var url = URLComponents(string: "https://www.wikidata.org/wiki/\(entityID ?? "")")!
        url.fragment = statementID
        return url.url!
    }
    var isValid: Bool {
        guard score.isFinite, (0...100).contains(score), !isCommunity || source == .igdb else { return false }
        if source == .igdb {
            let minimum = isCommunity ? 1 : IGDBRatings.minimumCriticReviews
            return (igdbID ?? 0) > 0 && (reviewCount ?? 0) >= minimum && igdbURL.flatMap(IGDBRatings.safeGameURL) != nil
        }
        guard let entityID, let statementID else { return false }
        return WikidataRatings.isItemID(entityID) && statementID.hasPrefix(entityID + "$")
            && (!referenceURLs.isEmpty || !referenceItems.isEmpty)
    }
}

public struct CriticRatingResult: Equatable, Sendable {
    public let rating: CriticRating?
    public let fetchedAt: Date?
    public let isStale: Bool
}
