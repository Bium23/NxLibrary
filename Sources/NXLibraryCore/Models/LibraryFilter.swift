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

    public func apply(to games: [PortedGame], history: PlayHistory) -> [PortedGame] {
        let visible = games.filter { !$0.isHidden }
        let dates = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, history.lastPlayed(for: $0.id)) })
        func played(_ game: PortedGame) -> Date? { dates[game.id] ?? nil }

        let filtered: [PortedGame]
        switch filter {
        case .all: filtered = visible
        case .installed: filtered = visible.filter(\.isPlayableLocally)
        case .recentlyPlayed: filtered = visible.filter { played($0) != nil }
        case .favorites: filtered = visible.filter(\.isFavorite)
        case .notPlayed: filtered = visible.filter { played($0) == nil }
        }

        let query = normalized(searchText)
        let searched = query.isEmpty ? filtered : filtered.filter { game in
            normalized(game.name).contains(query)
                || normalized(game.titleId ?? "").contains(query)
                || normalized(game.bundleId ?? "").contains(query)
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
