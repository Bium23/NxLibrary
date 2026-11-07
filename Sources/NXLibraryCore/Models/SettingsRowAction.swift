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
    /// A second button on the row for the controller's Y (named in the hints), such as Back to tested beside Update.
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

    public static func primaryActions(_ actions: [SettingsRowAction]) -> [SettingsRowAction] {
        var seen = Set<String>()
        return actions.filter { seen.insert($0.rowID).inserted }
    }
}
