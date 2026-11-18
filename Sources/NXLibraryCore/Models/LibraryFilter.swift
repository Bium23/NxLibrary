import Foundation

public protocol PlayHistory {
    func lastPlayed(for gameID: UUID) -> Date?
}

public struct NoPlayHistory: PlayHistory {
    public init() {}
    public func lastPlayed(for gameID: UUID) -> Date? { nil }
}

public enum LibraryFilter: String, CaseIterable, Identifiable, Equatable {
    case all = "All games"
    case installed = "Installed"
    case recentlyPlayed = "Recently played"
    case favorites = "Favorites"
    case notPlayed = "Not played yet"

    public var id: String { rawValue }
}

public struct LibraryQuery: Equatable {
    public var filter: LibraryFilter
    public var searchText: String

    public init(filter: LibraryFilter = .all, searchText: String = "") {
        self.filter = filter
        self.searchText = searchText
    }

    public func apply(to games: [PortedGame], history: PlayHistory) -> [PortedGame] { applyRecords(games, history: history) }
    public func applyCatalog(to games: [CatalogGame], history: PlayHistory) -> [CatalogGame] { applyRecords(games, history: history) }

    private func applyRecords<Game: LibraryQueryRecord>(_ games: [Game], history: PlayHistory) -> [Game] {
        let visible = games.filter { !$0.isHidden }
        let dates = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, history.lastPlayed(for: $0.id)) })
        func played(_ game: Game) -> Date? { dates[game.id] ?? nil }

        let filtered: [Game]
        switch filter {
        case .all: filtered = visible
        case .installed: filtered = visible.filter(\.isInstalledForLibrary)
        case .recentlyPlayed: filtered = visible.filter { played($0) != nil }
        case .favorites: filtered = visible.filter(\.isFavorite)
        case .notPlayed: filtered = visible.filter { played($0) == nil }
        }

        let query = normalized(searchText)
        let searched = query.isEmpty ? filtered : filtered.filter { game in
            normalized(game.name).contains(query)
                || game.librarySearchTerms.contains { normalized($0).contains(query) }
        }

        return searched.sorted { lhs, rhs in
            switch (played(lhs), played(rhs)) {
            case let (l?, r?) where l != r: return l > r
            case (.some, .none): return true
            case (.none, .some): return false
            default:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive],
                      locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


private protocol LibraryQueryRecord {
    var id: UUID { get }
    var name: String { get }
    var isFavorite: Bool { get }
    var isHidden: Bool { get }
    var isInstalledForLibrary: Bool { get }
    var librarySearchTerms: [String] { get }
}
extension PortedGame: LibraryQueryRecord {
    fileprivate var isInstalledForLibrary: Bool { isPlayableLocally }
    fileprivate var librarySearchTerms: [String] { [titleId, bundleId].compactMap { $0 } }
}
extension CatalogGame: LibraryQueryRecord {
    fileprivate var isInstalledForLibrary: Bool {
        if let game = nxnativeGame { return game.isPlayableLocally }
        guard let game = steamGame, game.hasBeenRecognized else { return false }
        return game.installations.contains { $0.availability == .available || ($0.availability == .requiresReview && $0.primaryApplication != nil) }
    }
    fileprivate var librarySearchTerms: [String] {
        switch payload {
        case .nxnative(let game): return game.librarySearchTerms
        case .steam(let game): return ["Steam", String(game.appID)] + game.installations.flatMap { $0.applications.compactMap(\.bundleIdentifier) }
        }
    }
}
