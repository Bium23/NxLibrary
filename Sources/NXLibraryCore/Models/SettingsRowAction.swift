import Foundation

/// Primary and secondary actions share a row identity. Dynamic rows supply an
/// explicit identity; fixed settings keep their existing label-based identity.
public struct SettingsRowAction: Identifiable {
    public let id: String
    public let rowID: String
    public let title: String
    public let isEnabled: Bool
    public let cycle: ((Int) -> Void)?
    public let activate: () -> Void
    /// A second button on the row, such as Back to tested beside Update: Right moves the focus to it, Left back.
    public let secondary: (title: String, activate: () -> Void)?

    public init(id: String, title: String, rowID: String? = nil, isEnabled: Bool = true,
                cycle: ((Int) -> Void)? = nil, secondary: (title: String, activate: () -> Void)? = nil,
                activate: @escaping () -> Void) {
        self.id = id
        self.rowID = rowID ?? title
        self.title = title
        self.isEnabled = isEnabled
        self.cycle = cycle
        self.activate = activate
        self.secondary = secondary
    }

    public static func value(_ id: String, _ title: String,
                             cycle: @escaping (Int) -> Void) -> SettingsRowAction {
        SettingsRowAction(id: id, title: title, cycle: cycle) { cycle(1) }
    }

    /// Buttons the focus can move between in this row.
    public var buttonCount: Int { secondary == nil ? 1 : 2 }

    /// Presses the row's button at `index` (0 the row's own, 1 the second); any other index presses the first.
    public func press(button index: Int) {
        if index == 1, let secondary { secondary.activate() } else { activate() }
    }

    public enum Sideways: Equatable { case button(Int), leaveRows, stay }

    /// Left and Right inside a row: between its buttons, and Left from the first one leaves the rows for the sidebar.
    public static func sideways(from index: Int, by delta: Int, buttons: Int) -> Sideways {
        let target = index + delta
        if target < 0 { return .leaveRows }
        return target < buttons && target != index ? .button(target) : .stay
    }

    public static func primaryActions(_ actions: [SettingsRowAction]) -> [SettingsRowAction] {
        var seen = Set<String>()
        return actions.filter { seen.insert($0.rowID).inserted }
    }
}
