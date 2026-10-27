import Foundation

public enum SettingsSection: String, CaseIterable, Identifiable, Equatable {
    case general, appearance, library, gameDefaults, controllers, engineKeys, storageLogs, about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .library: return "Library"
        case .gameDefaults: return "Game defaults"
        case .controllers: return "Controllers"
        case .engineKeys: return "Engine & keys"
        case .storageLogs: return "Storage & logs"
        case .about: return "About"
        }
    }

    public var subtitle: String {
        switch self {
        case .general: return "Startup, setup and readiness."
        case .appearance: return "How NX Library looks and moves."
        case .library: return "Folders, imports and artwork caches."
        case .gameDefaults: return "Defaults for newly added games."
        case .controllers: return "Gamepad, rumble and interface sounds."
        case .engineKeys: return "Engine pin, toolchain gate and keys."
        case .storageLogs: return "Caches, logs, saves and the console."
        case .about: return "Version, credits and licenses."
        }
    }

    public var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "paintpalette"
        case .library: return "square.grid.2x2"
        case .gameDefaults: return "play.rectangle"
        case .controllers: return "gamecontroller"
        case .engineKeys: return "cpu"
        case .storageLogs: return "externaldrive"
        case .about: return "info.circle"
        }
    }
}
