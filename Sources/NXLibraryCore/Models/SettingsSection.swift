import Foundation

/// The groups on the Settings screen (spec §5.7). `search` and `changed` are
/// computed lists; `about` is informational and has no catalog rows.
public enum SettingsSection: String, CaseIterable, Identifiable, Equatable {
    case search, changed, startUp, navigation, spotlight, soundMusic
    case look, games, controllers, library, sources, storage, engine, about

    public var id: String { rawValue }

    public var title: String { title(in: L10n.context) }

    public func title(in context: AppLocale) -> String {
        L10n.text(titleKey, context: context)
    }

    private var titleKey: String {
        switch self {
        case .search: return "Search"
        case .changed: return "Changed"
        case .startUp: return "Start-up"
        case .navigation: return "Navigation"
        case .spotlight: return "Spotlight"
        case .soundMusic: return "Sound & music"
        case .look: return "Look"
        case .games: return "Games"
        case .controllers: return "Controllers"
        case .library: return "Library"
        case .sources: return "Game sources"
        case .storage: return "Storage"
        case .engine: return "Engine"
        case .about: return "About"
        }
    }

    public var subtitle: String {
        switch self {
        case .search: return L10n.text("Find any setting by name or description.")
        case .changed: return L10n.text("Settings that differ from the defaults.")
        case .startUp: return L10n.text("Startup, setup and readiness.")
        case .navigation: return L10n.text("Button hints, button names and the View button.")
        case .spotlight: return L10n.text("Which cards show on Spotlight and where it opens.")
        case .soundMusic: return L10n.text("Interface sounds, volume and the launch screen.")
        case .look: return L10n.text("How NX Library looks and moves.")
        case .games: return L10n.text("Launch screen, hidden games and defaults for new games.")
        case .controllers: return L10n.text("Library controls and new-game rumble.")
        case .library: return L10n.text("Folders, imports and artwork caches.")
        case .sources: return L10n.text("Where NX Library finds your games.")
        case .storage: return L10n.text("Caches, logs, saves and the console.")
        case .engine: return L10n.text("Engine pin, toolchain gate and keys.")
        case .about: return L10n.text("Version, credits and licenses.")
        }
    }

    /// Glyphs from the bundled Material Icons font.
    public var icon: MaterialIcon {
        switch self {
        case .search: return .search
        case .changed: return .history
        case .startUp: return .rocket
        case .navigation: return .gamepad
        case .spotlight: return .spotlight
        case .soundMusic: return .volume
        case .look: return .palette
        case .games: return .play
        case .controllers: return .gamepad
        case .library: return .collections
        case .sources: return .collections
        case .storage: return .storage
        case .engine: return .build
        case .about: return .info
        }
    }
}
