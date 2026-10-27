import Foundation

public enum MenuAction: String, CaseIterable, Identifiable, Equatable {
    case library, addGame, settings, console, quit
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .library: return "Library"
        case .addGame: return "Add Game"
        case .settings: return "Settings"
        case .console: return "Console"
        case .quit: return "Quit"
        }
    }

    public var icon: String {
        switch self {
        case .library: return "square.grid.2x2"
        case .addGame: return "plus"
        case .settings: return "gearshape"
        case .console: return "terminal"
        case .quit: return "power"
        }
    }
}

public struct MenuSelectionModel: Equatable {
    public var selected: MenuAction = .settings
    public init(selected: MenuAction = .settings) { self.selected = selected }

    public mutating func move(by delta: Int) {
        let all = MenuAction.allCases
        guard let index = all.firstIndex(of: selected) else { return }
        let count = all.count
        let next = ((index + delta) % count + count) % count
        selected = all[next]
    }
}
