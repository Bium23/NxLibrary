import Foundation

/// One row on the Settings screen, as listed by Changed and Search.
public struct SettingDescriptor: Identifiable {
    /// The `AppSettings` property name when the row stores a value.
    public let id: String
    public let group: SettingsSection
    public let title: String
    public let about: String
    public let isChanged: (AppSettings) -> Bool

    public init(id: String, group: SettingsSection, title: String, about: String,
                isChanged: @escaping (AppSettings) -> Bool = { _ in false }) {
        self.id = id
        self.group = group
        self.title = title
        self.about = about
        self.isChanged = isChanged
    }
}

/// The Settings rows of the base, and the rules that order, compare and search any list of rows. The whole list,
/// with the Porting rows, is `SettingsCatalog.all` (`SettingsCatalog+Porting.swift`).
public enum SettingsCatalog {
    package static let defaults = AppSettings()

    package static func row<Value: Equatable>(_ id: String, _ group: SettingsSection, _ title: String,
                                      _ about: String,
                                      _ value: @escaping (AppSettings) -> Value) -> SettingDescriptor {
        SettingDescriptor(id: id, group: group, title: title, about: about) { value($0) != value(defaults) }
    }

    package static func action(_ id: String, _ group: SettingsSection, _ title: String,
                       _ about: String) -> SettingDescriptor {
        SettingDescriptor(id: id, group: group, title: title, about: about)
    }

    /// `rows` in sidebar order (`SettingsSidebarGroup`), each section's rows as listed.
    public static func ordered(_ rows: [SettingDescriptor]) -> [SettingDescriptor] {
        let order = SettingsSidebarGroup.all.flatMap(\.sections)
        return rows.enumerated().sorted {
            (order.firstIndex(of: $0.element.group) ?? order.count, $0.offset)
                < (order.firstIndex(of: $1.element.group) ?? order.count, $1.offset)
        }.map(\.element)
    }

    /// The rows of every section outside the Porting group, in screen order.
    public static let baseRows: [SettingDescriptor] = [
        // Start-up
        row("appLanguage", .startUp, "App language", "Menus, genres and available game descriptions. The games’ own language stays separate.") { $0.appLanguage },
        row("appRegion", .startUp, "Regional formats", "Dates, numbers and sizes only. Game descriptions follow the app language.") { $0.appRegion },
        row("startOn", .startUp, "Start on",
            "The screen Arcane opens on: Spotlight, Collection, or where you left it.") { $0.startOn },
        row("restoreLastGame", .startUp, "Restore last game",
            "Opens with the game you had selected last time.") { $0.restoreLastGame },
        row("startInFullscreen", .startUp, "Start in fullscreen",
            "Open Arcane in fullscreen. Applies at the next launch.") { $0.startInFullscreen },
        row("checkAppUpdatesAtLaunch", .startUp, "Check for app updates",
            "Looks for a newer Arcane release at launch, at most once a day.") { $0.checkAppUpdatesAtLaunch },
        row("introAnimation", .startUp, "Entrance animation",
            "The library's tiles fly in with the boot sound when the app opens.") { $0.introAnimation },

        // Navigation
        row("showButtonHints", .navigation, "Button hints",
            "Shows the button prompts along the bottom of the screen.") { $0.showButtonHints },
        row("buttonNames", .navigation, "Button names",
            "Which letters the prompts use: Nintendo, Xbox or PlayStation. Automatic follows the connected controller.") { $0.buttonNames },
        row("viewButtonSwitches", .navigation, "View button switches screens",
            "Pressing View flips between Spotlight and Collection; holding it opens Find a game.") { $0.viewButtonSwitches },

        // Spotlight
        row("spotlightCards", .spotlight, "Cards",
            "Which cards sit in the Spotlight row: Collection, Surprise me, Activity, Mods and Add game.") { $0.visibleSpotlightCards },
        row("startingTab", .spotlight, "Starting tab",
            "The filter Spotlight and Collection open on.") { $0.startingTab },
        row("spotlightOrder", .spotlight, "Tile order",
            "Your own order of games and cards on Spotlight. Reset puts everything back in place.") { $0.spotlightOrder },

        // Sound & music
        row("interfaceSounds", .soundMusic, "Interface sounds",
            "Plays a short sound when you move, select, go back or launch a game.") { $0.interfaceSounds },
        row("soundVolume", .soundMusic, "Sound volume",
            "How loud the interface sounds are.") { $0.soundVolume },
        row("quietLaunch", .soundMusic, "Quiet launch screen",
            "Game cues only during launch; movement and selection sounds stay quiet.") { $0.quietLaunch },
        action("importSeleneSounds", .soundMusic, "Import sounds and wallpapers from Selene",
               "Copies optional sounds and wallpapers from a local Selene folder you own."),

        // Look
        row("colorThemeID", .look, "Color theme",
            "The palette for focus, text and backgrounds.") { $0.colorThemeID },
        row("wallpaperID", .look, "Wallpaper",
            "The picture behind the base gradient, per theme or none.") { $0.wallpaperID },
        row("settingsWallpaperID", .look, "Settings wallpaper",
            "The picture behind Settings: the same as the app's, or one of its own.") { $0.settingsWallpaperID },
        row("backgroundSizing", .look, "Wallpaper sizing",
            "Fill crops the picture to cover the screen, Fit shows all of it, Stretch distorts it to fit.") { $0.backgroundSizing },
        row("wallpaperBrightness", .look, "Wallpaper brightness",
            "How dark a wallpaper or live background is: dim evenly, bright on the right away from the text, or bright everywhere.") { $0.wallpaperBrightness },
        row("animatedBackground", .look, "Background motion",
            "The moonlight's beam and motes move and a live background plays; off, they hold still.") { $0.animatedBackground },
        row("keepWallpaperOnGames", .look, "Game backgrounds",
            "On shows the selected game's art in Spotlight and Collection; Off keeps your wallpaper. Details keeps the game's art.") { $0.keepWallpaperOnGames },
        row("backgroundShade", .look, "Library shade",
            "Shading behind library text, over game artwork or your wallpaper.") { $0.backgroundShade },
        row("readableText", .look, "Text shadow",
            "Adds a soft shadow under text so it reads over bright art.") { $0.readableText },
        row("showClock", .look, "Clock",
            "Shows the time in the top bar.") { $0.showClock },
        row("reduceMotion", .look, "Reduce motion",
            "Replaces slides and zooms with fades.") { $0.reduceMotion },
        action("iconAppearance", .look, "App icon", "The icon appearance in the Dock."),
        // Optional connections shared by all library platforms.
        action("igdb", .apiServices, "IGDB", "Personal IGDB credentials for critic scores. Wikidata remains available without a key."),
        action("steamGridDB", .apiServices, "SteamGridDB", "Add your API key to find covers, backgrounds, logos and icons in Change artwork."),

        // Games (Library)
        row("launchStyle", .libraryGames, "Launch screen style",
            "What shows while a game starts: art and logo, art only, logo on black, or minimal.") { $0.launchStyle },
        row("launchMotion", .libraryGames, "Launch screen motion",
            "A slow drift of the art while the game starts.") { $0.launchMotion },
        row("launchShade", .libraryGames, "Launch screen shade",
            "How much the launch art is darkened.") { $0.launchShade },
        row("surprisePool", .libraryGames, "Surprise me pool",
            "Which games Surprise me picks from.") { $0.surprisePool },
        row("showsSessionCard", .libraryGames, "Session card",
            "When you close a game, a card shows how long you played this time and in total.") { $0.showsSessionCard },
        action("hiddenGames", .libraryGames, "Hidden games",
               "Games you hid from Game options; Show puts one back in your lists."),

        // Controllers
        action("controllerStatus", .controllers, "Gamepad",
               "The connected controller and how its buttons map."),
        action("buttonLayout", .controllers, "Button layout", "View the library controls."),
        action("controllerDeadzone", .controllers, "Stick navigation deadzone",
               "Thumbstick threshold for library navigation; does not alter game input."),

        // Steam
        action("steamSource", .sources, "Steam", "Find installed native Mac games in your Steam libraries."),
        action("steamRefresh", .sources, "Refresh Steam", "Check enabled Steam libraries without changing your game files."),
        action("steamFolder", .sources, "Steam folder", "Choose the Steam folder containing steamapps."),
        row("steamInBackground", .sources, "Keep Steam in the background",
            "Steam starts quietly when possible and comes forward if it needs you.") { $0.steamInBackground },

        // Storage
        action("storageUsage", .storage, "Storage usage", "See per-game app, cache and log sizes and free disk space."),
        action("logs", .storage, "Logs", "Delete build and launch logs after confirmation."),
        action("metadataCache", .storage, "Metadata cache", "Clear cached store descriptions and links."),
        action("artworkCache", .storage, "Artwork cache", "Clear downloaded images; manual picks are kept."),
        action("saveBackups", .storage, "Save backups", "Open the folder of verified per-game backups."),
        action("console", .console, "Console", "View, search and copy logs."),

        // About
        action("diagnostics", .about, "Copy diagnostics", "Copy a scrubbed support report."),
        action("appUpdates", .about, "App updates", "Check now, update or read release notes."),
        action("projectDocs", .about, "Open project docs", "Open the project documentation."),
    ]

    public static func changed(in settings: AppSettings, externalChanges: Set<String> = [],
                               rows: [SettingDescriptor]) -> [SettingDescriptor] {
        rows.filter { $0.isChanged(settings) || externalChanges.contains($0.id) }
    }

    /// Case- and diacritic-insensitive match over title and about.
    public static func search(_ query: String, in rows: [SettingDescriptor]) -> [SettingDescriptor] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return rows.filter {
            $0.title.range(of: needle, options: options) != nil
                || L10n.text($0.title).range(of: needle, options: options) != nil
                || L10n.text($0.about).range(of: needle, options: options) != nil
                || $0.about.range(of: needle, options: options) != nil
        }
    }
}
