import Foundation

/// Public lookup identity only. Never sends catalog paths, account IDs or play history.
public struct CriticRatingQuery: Hashable, Codable, Sendable {
    public enum Platform: String, Codable, Sendable {
        case mac, `switch`
        var wikidataID: String { self == .mac ? "Q14116" : "Q19610114" }
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

/// One referenced critic average, never an audience recommendation or an average of providers.
public struct CriticRating: Equatable, Codable, Sendable {
    public enum Source: String, Codable, Sendable {
        case openCritic, metacritic, criticDB
        public var name: String {
            switch self {
            case .openCritic: return "OpenCritic"
            case .metacritic: return "Metacritic"
            case .criticDB: return "CriticDB"
            }
        }
        var priority: Int {
            switch self { case .openCritic: return 0; case .metacritic: return 1; case .criticDB: return 2 }
        }
    }
    public let score: Double
    public let source: Source
    public let entityID: String
    public let statementID: String
    public let referenceURLs: [URL]
    public let referenceItems: [String]
    /// Wikidata's point-in-time, not the date the app fetched this value.
    public let scoreDate: String?
    /// Empty means platform unspecified; never inferred from the requesting game's platform.
    public let platforms: [String]

    public var starFills: [Double] { (0..<5).map { max(0, min(1, score / 20 - Double($0))) } }
    public func number(locale: Locale = L10n.context.formatLocale) -> String {
        score.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + "/100"
    }
    public var sourceURL: URL {
        var url = URLComponents(string: "https://www.wikidata.org/wiki/\(entityID)")!
        url.fragment = statementID
        return url.url!
    }
    var isValid: Bool {
        score.isFinite && (0...100).contains(score) && WikidataRatings.isItemID(entityID)
            && statementID.hasPrefix(entityID + "$") && (!referenceURLs.isEmpty || !referenceItems.isEmpty)
    }
}

public struct CriticRatingResult: Equatable, Sendable {
    public let rating: CriticRating?
    public let fetchedAt: Date?
    public let isStale: Bool
}
