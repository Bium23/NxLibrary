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

/// Every Settings row (spec §5.7), in screen order.
public enum SettingsCatalog {
    private static let defaults = AppSettings()

    private static func row<Value: Equatable>(_ id: String, _ group: SettingsSection, _ title: String,
                                              _ about: String,
                                              _ value: @escaping (AppSettings) -> Value) -> SettingDescriptor {
        SettingDescriptor(id: id, group: group, title: title, about: about) { value($0) != value(defaults) }
    }

    private static func action(_ id: String, _ group: SettingsSection, _ title: String,
                               _ about: String) -> SettingDescriptor {
        SettingDescriptor(id: id, group: group, title: title, about: about)
    }

    public static let all: [SettingDescriptor] = [
        // Start-up
        row("startOn", .startUp, "Start on",
            "The screen NX Library opens on: Spotlight, Collection, or where you left it.") { $0.startOn },
        row("restoreLastGame", .startUp, "Restore last game",
            "Opens with the game you had selected last time.") { $0.restoreLastGame },
        row("checkEngineAtLaunch", .startUp, "Check engine at launch",
            "Checks the engine and toolchain each time NX Library starts.") { $0.checkEngineAtLaunch },
        row("refreshLibraryAtLaunch", .startUp, "Refresh library at launch",
            "Scans your library folders for new or removed games at start.") { $0.refreshLibraryAtLaunch },
        row("introAnimation", .startUp, "Intro animation",
            "Plays the app mark when NX Library opens.") { $0.introAnimation },

        // Navigation
        row("showButtonHints", .navigation, "Button hints",
            "Shows the button prompts along the bottom of the screen.") { $0.showButtonHints },
        row("buttonNames", .navigation, "Button names",
            "Which letters the prompts use: Nintendo, Xbox or PlayStation. Automatic follows the connected controller.") { $0.buttonNames },
        row("viewButtonSwitches", .navigation, "View button switches screens",
            "Pressing View flips between Spotlight and Collection; holding it opens Find a game.") { $0.viewButtonSwitches },

        // Spotlight
        row("spotlightCards", .spotlight, "Cards",
            "Which cards sit in the Spotlight row: Collection, Surprise me, Activity and Add game.") { $0.spotlightCards },
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
            "Keeps the launch screen silent while a game starts.") { $0.quietLaunch },
        action("importSeleneSounds", .soundMusic, "Import sounds",
               "Copies optional sounds and wallpapers from a local Selene folder you own."),

        // Look
        row("colorThemeID", .look, "Color theme",
            "The palette for focus, text and backgrounds.") { $0.colorThemeID },
        row("wallpaperID", .look, "Wallpaper",
            "The picture behind the base gradient, per theme or none.") { $0.wallpaperID },
        row("backgroundSizing", .look, "Background sizing",
            "Fill crops the picture to cover the screen, Fit shows all of it, Stretch distorts it to fit.") { $0.backgroundSizing },
        row("backgroundShade", .look, "Background shade",
            "How much the game art is darkened behind text.") { $0.backgroundShade },
        row("readableText", .look, "Text shadow",
            "Adds a soft shadow under text so it reads over bright art.") { $0.readableText },
        row("animatedBackground", .look, "Animated background",
            "Without a wallpaper: the theme's breathing light beam and drifting motes move; off, they hold still.") { $0.animatedBackground },
        row("showClock", .look, "Clock",
            "Shows the time in the top bar.") { $0.showClock },
        row("reduceMotion", .look, "Reduce motion",
            "Replaces slides and zooms with fades.") { $0.reduceMotion },

        // Games
        row("launchStyle", .games, "Launch screen style",
            "What shows while a game starts: art and logo, art only, logo on black, or minimal.") { $0.launchStyle },
        row("launchMotion", .games, "Launch screen motion",
            "A slow drift of the art while the game starts.") { $0.launchMotion },
        row("launchShade", .games, "Launch screen shade",
            "How much the launch art is darkened.") { $0.launchShade },
        row("surprisePool", .games, "Surprise me pool",
            "Which games Surprise me picks from.") { $0.surprisePool },
        row("cloudSaves", .games, "Cloud saves",
            "One folder every game syncs its save through, shared with the games' iPhone apps: off, iCloud Drive or a folder you choose.") { $0.cloudSaves },
        action("hiddenGames", .games, "Hidden games",
               "Games you hid from Game options; Show puts one back in your lists."),
        row("gameDefaults", .games, "Game defaults",
            "Runtime options new games start with: frame rate, upscaling, console mode, language and rumble.") { $0.gameDefaults },

        // Controllers
        action("controllerStatus", .controllers, "Controller",
               "The connected controller and how its buttons map."),

        // Library
        action("libraryFolders", .library, "Library folders",
               "Where NX Library looks for ported games."),
        action("importBuilds", .library, "Import existing builds",
               "Adds games you already built to the library."),

        // Storage
        action("clearCaches", .storage, "Clear caches",
               "Removes downloaded artwork and store metadata. They load again when needed."),
        action("openLogs", .storage, "Logs",
               "Opens the folder with NX Library and build logs."),

        // Engine
        action("engineStatus", .engine, "Engine",
               "The pinned engine commit, the toolchain gate and your keys."),
    ]

    public static func changed(in settings: AppSettings) -> [SettingDescriptor] {
        all.filter { $0.isChanged(settings) }
    }

    /// Case- and diacritic-insensitive match over title and about.
    public static func search(_ query: String) -> [SettingDescriptor] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return all.filter {
            $0.title.range(of: needle, options: options) != nil
                || $0.about.range(of: needle, options: options) != nil
        }
    }
}
