import Foundation

/// The sections on the Settings screen. `search` and `changed` are computed lists.
public enum SettingsSection: String, CaseIterable, Identifiable, Equatable {
    // Declared in sidebar order (`SettingsSidebarGroup`), so `allCases` steps through it as drawn.
    // Raw values are identities and never change: `sources` is the Sources page, `library` and
    // `games` are Porting's Library and New games.
    case search, changed
    case startUp, navigation, spotlight, soundMusic, look, controllers, apiServices
    case sources, libraryGames, storage
    case engine, keys, library, games, cloudSaves, portingStorage
    case about, console

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
        case .apiServices: return "Online services"
        case .controllers: return "Controllers"
        case .sources: return "Settings section: Sources"
        case .libraryGames: return "Games"
        case .storage: return "Storage"
        case .engine: return "Setup and engine"
        case .keys: return "Keys"
        case .library: return "Library"
        case .games: return "New games"
        case .cloudSaves: return "Cloud saves"
        case .portingStorage: return "Storage"
        case .about: return "About"
        case .console: return "Console"
        }
    }

    public var subtitle: String {
        switch self {
        case .search: return L10n.text("Find any setting by name or description.")
        case .changed: return L10n.text("Settings that differ from the defaults.")
        case .startUp: return L10n.text("Language, the first screen and what runs at launch.")
        case .navigation: return L10n.text("Button hints, button names and the View button.")
        case .spotlight: return L10n.text("Which cards show on Spotlight and where it opens.")
        case .soundMusic: return L10n.text("Interface sounds, volume and the launch screen.")
        case .look: return L10n.text("How Arcane looks and moves.")
        case .apiServices: return L10n.text("Optional connections for ratings and game artwork.")
        case .controllers: return L10n.text("Gamepad, button layout and stick deadzone for the library.")
        case .sources: return L10n.text("Steam libraries, refresh and how Play opens Steam.")
        case .libraryGames: return L10n.text("Launch screen, Surprise me, session card and hidden games.")
        case .storage: return L10n.text("Storage usage, logs, metadata and artwork caches, save backups.")
        case .engine: return L10n.text("Engine pin, toolchain gate and setup.")
        case .keys: return L10n.text("Import, replace or detect prod.keys.")
        case .library: return L10n.text("Folders, scans and box covers.")
        case .games: return L10n.text("Defaults copied into each new ported game.")
        case .cloudSaves: return L10n.text("Save sync for ported games: Off, iCloud Drive or a folder.")
        case .portingStorage: return L10n.text("Build caches for each game and for all games.")
        case .about: return L10n.text("Version, credits and licenses.")
        case .console: return L10n.text("Filter, search and copy build and launch logs.")
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
        case .apiServices: return .link
        case .controllers: return .gamepad
        case .sources: return .collections
        case .libraryGames: return .play
        case .storage: return .storage
        case .engine: return .build
        case .keys: return .key
        case .library: return .collections
        case .games: return .tune
        case .cloudSaves: return .sync
        case .portingStorage: return .folder
        case .about: return .info
        case .console: return .terminal
        }
    }

    public var group: SettingsSidebarGroup {
        SettingsSidebarGroup.all.first { $0.sections.contains(self) } ?? SettingsSidebarGroup.all[0]
    }

    /// The name Search and Changed show: a platform's section carries its group ("Porting · New games").
    public var place: String { place(in: L10n.context) }

    public func place(in context: AppLocale) -> String {
        guard group.isPlatform, let heading = group.title(in: context) else { return title(in: context) }
        return "\(heading) · \(title(in: context))"
    }
}

/// The sidebar's groups, in order: app-wide settings, the library of every source, the Porting
/// platform, then System. A heading is a label, never a stop.
public struct SettingsSidebarGroup: Identifiable, Equatable {
    /// Localization key ("Settings group: Porting"); the first group has none.
    public let heading: String?
    public let sections: [SettingsSection]
    /// A platform's group: its settings act only on that platform's games.
    public let isPlatform: Bool

    public var id: String { heading ?? "top" }

    /// The heading as drawn, from its own key so a bare word is never translated as a verb.
    public var title: String? { title(in: L10n.context) }

    public func title(in context: AppLocale) -> String? {
        heading.map { L10n.text($0, context: context) }
    }

    public static let all: [SettingsSidebarGroup] = [
        .init(heading: nil, sections: [.search, .changed], isPlatform: false),
        .init(heading: "Settings group: General", sections: [.startUp, .navigation, .spotlight, .soundMusic, .look, .controllers, .apiServices], isPlatform: false),
        .init(heading: "Settings group: Library", sections: [.sources, .libraryGames, .storage], isPlatform: false),
        .init(heading: "Settings group: Porting", sections: [.engine, .keys, .library, .games, .cloudSaves, .portingStorage], isPlatform: true),
        .init(heading: "Settings group: System", sections: [.about, .console], isPlatform: false),
    ]
}
