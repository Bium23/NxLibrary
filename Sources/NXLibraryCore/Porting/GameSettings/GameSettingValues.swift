import Foundation

extension GameSettingsSnapshot {
    /// The settings the build offers that no main-list row shows, for More settings, in the build's order.
    public var extraSettings: [LauncherSetting] {
        let shown = Set(GameOptionsRow.settingRows.compactMap(\.settingKey))
        return settings.filter { !shown.contains($0.env) }
    }
}

/// Labels and steps for a setting drawn from the build's list.
public enum GameSettingValues {
    /// A choice's option label, On / Off for a toggle, a percentage for a range (as the engine's window shows it).
    public static func label(_ setting: LauncherSetting, _ value: String) -> String {
        switch setting.kind {
        case "toggle": return value == setting.on ? L10n.text("On") : L10n.text("Off")
        case "range":
            guard let x = LauncherSetting.number(value) else { return value }
            return "\(Int((x * 100).rounded()))%"
        default: return setting.options?.first { $0.value == value }?.label ?? value
        }
    }

    /// The next value in the direction, wrapping at the ends as the other value rows do.
    public static func stepped(_ setting: LauncherSetting, from value: String, by delta: Int) -> String {
        switch setting.kind {
        case "toggle":
            return value == setting.on ? (setting.off ?? value) : (setting.on ?? value)
        case "range":
            guard let min = setting.min, let max = setting.max, max >= min else { return value }
            let step = (setting.step ?? 0.1) > 0 ? (setting.step ?? 0.1) : 0.1
            let count = Int(((max - min) / step).rounded())
            let stops = (0...count).map { Swift.min(max, min + Double($0) * step) }
            let x = LauncherSetting.number(value) ?? setting.defaultValue.flatMap(LauncherSetting.number) ?? min
            let next = delta > 0
                ? (stops.first { $0 > x + 1e-9 } ?? stops[0])
                : (stops.last { $0 < x - 1e-9 } ?? stops[stops.count - 1])
            return LauncherSetting.rangeString(next)
        default:
            let options = setting.options ?? []
            guard !options.isEmpty else { return value }
            let index = options.firstIndex { $0.value == value }
            return options[GameOptionsValues.steppedIndex(index, by: delta, count: options.count)].value
        }
    }
}
