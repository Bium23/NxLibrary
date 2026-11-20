import Foundation
import NXLibraryCore

/// The library's filter and selection for the Switch games the home lists today (`AppViewModel.libraryGames`).
extension PortedGame: LibraryQueryRecord {}

extension LibraryQuery {
    public func apply(to games: [PortedGame], history: PlayHistory) -> [PortedGame] { applyRecords(games, history: history) }
}

extension LibrarySelectionState {
    @discardableResult
    public mutating func reconcile(with games: [PortedGame], history: PlayHistory, preferredGameID: UUID? = nil) -> [PortedGame] {
        let filtered = query.apply(to: games, history: history)
        reconcileIDs(filtered.map(\.id), preferred: preferredGameID)
        return filtered
    }
    @discardableResult
    public mutating func move(by delta: Int, in games: [PortedGame], history: PlayHistory) -> UUID? {
        moveIDs(query.apply(to: games, history: history).map(\.id), by: delta)
    }
    @discardableResult
    public mutating func jump(toEnd: Bool, in games: [PortedGame], history: PlayHistory) -> UUID? {
        jumpIDs(query.apply(to: games, history: history).map(\.id), toEnd: toEnd)
    }
}
