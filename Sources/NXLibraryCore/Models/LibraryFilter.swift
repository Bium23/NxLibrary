import Foundation

public enum LibraryFilter: String, CaseIterable, Identifiable, Equatable {
    case all = "All games"
    case ready = "Ready"
    case needsSources = "Needs sources"
    case recentlyAdded = "Recently added"

    public var id: String { rawValue }
}

public struct LibraryQuery: Equatable {
    public var filter: LibraryFilter
    public var searchText: String

    public init(filter: LibraryFilter = .all, searchText: String = "") {
        self.filter = filter
        self.searchText = searchText
    }

    public func apply(to games: [PortedGame]) -> [PortedGame] {
        let filtered: [PortedGame]
        switch filter {
        case .all:
            filtered = games
        case .ready:
            filtered = games.filter(\.isPlayableLocally)
        case .needsSources:
            filtered = games.filter { game in
                !game.sources.contains { $0.type == .base }
            }
        case .recentlyAdded:
            filtered = games.sorted {
                if $0.modificationDate != $1.modificationDate {
                    return $0.modificationDate > $1.modificationDate
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        let query = normalized(searchText)
        let searched = query.isEmpty ? filtered : filtered.filter { game in
            normalized(game.name).contains(query)
                || normalized(game.titleId ?? "").contains(query)
                || normalized(game.bundleId ?? "").contains(query)
        }

        if filter == .recentlyAdded { return searched }
        return searched.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive],
                      locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
