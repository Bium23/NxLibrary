import Foundation

/// The shared home filter and stable UUID selection, independent of integration.
public struct LibrarySelectionState: Equatable {
    public var query: LibraryQuery
    public var selectedGameID: UUID?
    public init(query: LibraryQuery = LibraryQuery(), selectedGameID: UUID? = nil) {
        self.query = query; self.selectedGameID = selectedGameID
    }
    @discardableResult
    public mutating func reconcile(with games: [PortedGame], history: PlayHistory, preferredGameID: UUID? = nil) -> [PortedGame] {
        let filtered = query.apply(to: games, history: history)
        reconcileIDs(filtered.map(\.id), preferred: preferredGameID)
        return filtered
    }
    @discardableResult
    public mutating func reconcileCatalog(with games: [CatalogGame], history: PlayHistory, preferredGameID: UUID? = nil) -> [CatalogGame] {
        let filtered = query.applyCatalog(to: games, history: history)
        reconcileIDs(filtered.map(\.id), preferred: preferredGameID)
        return filtered
    }
    @discardableResult
    public mutating func move(by delta: Int, in games: [PortedGame], history: PlayHistory) -> UUID? {
        moveIDs(query.apply(to: games, history: history).map(\.id), by: delta)
    }
    @discardableResult
    public mutating func moveCatalog(by delta: Int, in games: [CatalogGame], history: PlayHistory) -> UUID? {
        moveIDs(query.applyCatalog(to: games, history: history).map(\.id), by: delta)
    }
    @discardableResult
    public mutating func jump(toEnd: Bool, in games: [PortedGame], history: PlayHistory) -> UUID? {
        jumpIDs(query.apply(to: games, history: history).map(\.id), toEnd: toEnd)
    }
    @discardableResult
    public mutating func jumpCatalog(toEnd: Bool, in games: [CatalogGame], history: PlayHistory) -> UUID? {
        jumpIDs(query.applyCatalog(to: games, history: history).map(\.id), toEnd: toEnd)
    }
    private mutating func reconcileIDs(_ ids: [UUID], preferred: UUID?) {
        if let selectedGameID, ids.contains(selectedGameID) { return }
        selectedGameID = preferred.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
    }
    private mutating func moveIDs(_ ids: [UUID], by delta: Int) -> UUID? {
        guard !ids.isEmpty else { selectedGameID = nil; return nil }
        let current = ids.firstIndex { $0 == selectedGameID } ?? 0
        selectedGameID = ids[min(max(current + delta, 0), ids.count - 1)]
        return selectedGameID
    }
    private mutating func jumpIDs(_ ids: [UUID], toEnd: Bool) -> UUID? {
        selectedGameID = toEnd ? ids.last : ids.first
        return selectedGameID
    }
}
