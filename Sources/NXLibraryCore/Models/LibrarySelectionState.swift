import Foundation

public enum LibraryFocusArea: String, Equatable {
    case filters, actions, rail
}

public struct LibrarySelectionState: Equatable {
    public var query: LibraryQuery
    public var selectedGameID: UUID?
    public var focusArea: LibraryFocusArea
    public var actionIndex: Int
    public var filterIndex: Int

    public init(query: LibraryQuery = LibraryQuery(),
                selectedGameID: UUID? = nil,
                focusArea: LibraryFocusArea = .rail,
                actionIndex: Int = 0,
                filterIndex: Int = 0) {
        self.query = query
        self.selectedGameID = selectedGameID
        self.focusArea = focusArea
        self.actionIndex = actionIndex
        self.filterIndex = filterIndex
    }

    @discardableResult
    public mutating func reconcile(with games: [PortedGame]) -> [PortedGame] {
        let filtered = query.apply(to: games)
        if let selectedGameID,
           filtered.contains(where: { $0.id == selectedGameID }) {
            return filtered
        }
        selectedGameID = filtered.first?.id
        actionIndex = 0
        return filtered
    }

    @discardableResult
    public mutating func move(by delta: Int, in games: [PortedGame]) -> UUID? {
        let filtered = query.apply(to: games)
        guard !filtered.isEmpty else {
            selectedGameID = nil
            return nil
        }
        let current = filtered.firstIndex { $0.id == selectedGameID } ?? 0
        let next = min(max(current + delta, 0), filtered.count - 1)
        selectedGameID = filtered[next].id
        return selectedGameID
    }
}
