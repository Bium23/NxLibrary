import Foundation

/// The library filter and the game selected on the Collection screen. The
/// filter is shared with Spotlight (both read `query.filter`).
public struct LibrarySelectionState: Equatable {
    public var query: LibraryQuery
    public var selectedGameID: UUID?

    public init(query: LibraryQuery = LibraryQuery(),
                selectedGameID: UUID? = nil) {
        self.query = query
        self.selectedGameID = selectedGameID
    }

    @discardableResult
    public mutating func reconcile(with games: [PortedGame], history: PlayHistory,
                                   preferredGameID: UUID? = nil) -> [PortedGame] {
        let filtered = query.apply(to: games, history: history)
        if let selectedGameID,
           filtered.contains(where: { $0.id == selectedGameID }) {
            return filtered
        }
        if let preferredGameID, filtered.contains(where: { $0.id == preferredGameID }) {
            selectedGameID = preferredGameID
        } else {
            selectedGameID = filtered.first?.id
        }
        return filtered
    }

    @discardableResult
    public mutating func move(by delta: Int, in games: [PortedGame], history: PlayHistory) -> UUID? {
        let filtered = query.apply(to: games, history: history)
        guard !filtered.isEmpty else {
            selectedGameID = nil
            return nil
        }
        let current = filtered.firstIndex { $0.id == selectedGameID } ?? 0
        let next = min(max(current + delta, 0), filtered.count - 1)
        selectedGameID = filtered[next].id
        return selectedGameID
    }

    /// Selects the first or last game of the filtered list (LT / RT).
    @discardableResult
    public mutating func jump(toEnd: Bool, in games: [PortedGame], history: PlayHistory) -> UUID? {
        let filtered = query.apply(to: games, history: history)
        selectedGameID = (toEnd ? filtered.last : filtered.first)?.id
        return selectedGameID
    }
}
