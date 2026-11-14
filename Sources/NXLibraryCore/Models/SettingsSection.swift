import Foundation

/// The groups on the Settings screen (spec §5.7). `search` and `changed` are
/// computed lists; `about` is informational and has no catalog rows.
public enum SettingsSection: String, CaseIterable, Identifiable, Equatable {
    // Sidebar order (`SettingsSidebarGroup`). Raw values are identities: `sources` is Steam's page.
    case search, changed, startUp, navigation, spotlight, soundMusic, look, controllers
    case library, games, engine
    case sources
    case storage, about

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
        case .sources: return "Library"
        case .storage: return "Storage"
        case .engine: return "Engine"
        case .about: return "About"
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
        case .look: return L10n.text("How NX Library looks and moves.")
        case .games: return L10n.text("Launch screen, hidden games and defaults for new games.")
        case .controllers: return L10n.text("Library controls and rumble for new Switch games.")
        case .library: return L10n.text("Folders, scans and box covers.")
        case .sources: return L10n.text("Steam libraries, refresh and how Play opens Steam.")
        case .storage: return L10n.text("Caches, logs, saves and the console.")
        case .engine: return L10n.text("Engine pin, toolchain gate, keys and setup.")
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

    public var group: SettingsSidebarGroup {
        SettingsSidebarGroup.all.first { $0.sections.contains(self) } ?? SettingsSidebarGroup.all[0]
    }

    /// The name Search and Changed show: a platform's section carries its platform ("Steam · Library").
    public var place: String { place(in: L10n.context) }

    public func place(in context: AppLocale) -> String {
        guard group.isPlatform, let heading = group.title(in: context) else { return title(in: context) }
        return "\(heading) · \(title(in: context))"
    }
}

/// The sidebar's groups, in order: app-wide settings first, then one group per platform,
/// so Switch and Steam settings never share a section. A heading is a label, never a stop.
public struct SettingsSidebarGroup: Identifiable, Equatable {
    /// Localization key ("Settings group: Switch"); the first group has none.
    public let heading: String?
    public let sections: [SettingsSection]
    /// A platform's group: its settings act only on that platform's games.
    public let isPlatform: Bool

    public var id: String { heading ?? "top" }

    /// The heading as drawn: "Switch", never the verb a bare "Switch" key translates to.
    public var title: String? { title(in: L10n.context) }

    public func title(in context: AppLocale) -> String? {
        heading.map { L10n.text($0, context: context) }
    }

    public static let all: [SettingsSidebarGroup] = [
        .init(heading: nil, sections: [.search, .changed], isPlatform: false),
        .init(heading: "Settings group: General", sections: [.startUp, .navigation, .spotlight, .soundMusic, .look, .controllers], isPlatform: false),
        .init(heading: "Settings group: Switch", sections: [.library, .games, .engine], isPlatform: true),
        .init(heading: "Settings group: Steam", sections: [.sources], isPlatform: true),
        .init(heading: "Settings group: System", sections: [.storage, .about], isPlatform: false),
    ]
}
