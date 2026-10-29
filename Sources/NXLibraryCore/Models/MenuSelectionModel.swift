import Foundation

/// The control-center row, left to right (Selene's menu.png).
public enum MenuAction: String, CaseIterable, Identifiable, Equatable {
    case addGame, refreshLibrary, settings, console, setupCheck, power
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .addGame: return "Add Game"
        case .refreshLibrary: return "Library refresh"
        case .settings: return "Settings"
        case .console: return "Console"
        case .setupCheck: return "Setup check"
        case .power: return "Power"
        }
    }

    public var icon: MaterialIcon {
        switch self {
        case .addGame: return .add
        case .refreshLibrary: return .sync
        case .settings: return .tune
        case .console: return .terminal
        case .setupCheck: return .checklist
        case .power: return .power
        }
    }
}

/// The pills stacked above Power.
public enum PowerAction: String, CaseIterable, Identifiable, Equatable {
    case quit, hide, relaunch
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .quit: return "Quit"
        case .hide: return "Hide"
        case .relaunch: return "Restart app"
        }
    }

    public var icon: MaterialIcon {
        switch self {
        case .quit: return .power
        case .hide: return .hidden
        case .relaunch: return .restartAlt
        }
    }
}

/// Focus on the control-center row, and on the Power pills when they are open.
/// Row moves clamp at the ends; the Power pills clamp too.
public struct MenuSelectionModel: Equatable {
    public var selected: MenuAction
    /// The focused pill while the Power pills are open.
    public var power: PowerAction = .quit
    public private(set) var isPowerOpen = false

    /// Opens on Power, as Selene's menu does.
    public init(selected: MenuAction = .power) { self.selected = selected }

    public mutating func move(by delta: Int) {
        let all = MenuAction.allCases
        guard let index = all.firstIndex(of: selected) else { return }
        let next = min(max(index + delta, 0), all.count - 1)
        selected = all[next]
    }

    public mutating func movePower(by delta: Int) {
        let all = PowerAction.allCases
        guard let index = all.firstIndex(of: power) else { return }
        let next = min(max(index + delta, 0), all.count - 1)
        power = all[next]
    }

    /// Opens the Power pills with Quit focused.
    public mutating func openPower() {
        power = .quit
        isPowerOpen = true
    }

    public mutating func closePower() {
        isPowerOpen = false
    }
}
