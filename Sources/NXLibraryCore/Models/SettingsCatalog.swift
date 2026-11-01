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
        row("checkAppUpdatesAtLaunch", .startUp, "Check for app updates",
            "Looks for a newer NX Library release at launch, at most once a day.") { $0.checkAppUpdatesAtLaunch },
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
            "How dark a wallpaper or live background is: dim like Selene, bright on the right away from the text, or bright everywhere.") { $0.wallpaperBrightness },
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
        action("boxCovers", .look, "Box covers", "Open GameTDB for box covers."),

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
            "One sync choice for all games, applied at next launch: Off, iCloud Drive or a folder you choose.") { $0.cloudSaves },
        row("cloudSavesPickedFolder", .games, "Cloud saves folder",
            "The chosen folder for save sync; choosing a folder enables it.") { $0.cloudSavesPickedFolder },
        action("hiddenGames", .games, "Hidden games",
               "Games you hid from Game options; Show puts one back in your lists."),
        row("gameDefaults.fullscreen", .games, "Fullscreen",
            "New games: start in fullscreen or a window.") { $0.gameDefaults.fullscreen },
        row("gameDefaults.enable60FPS", .games, "60 FPS",
            "New games: frame-rate target of 30 or 60 FPS.") { $0.gameDefaults.enable60FPS },
        row("gameDefaults.isDockedMode", .games, "Docked mode",
            "New games: console profile or handheld mode.") { $0.gameDefaults.isDockedMode },
        row("gameDefaults.enableMetalFXUpscale", .games, "MetalFX spatial upscaling",
            "New games: spatial upscaling of the presented picture.") { $0.gameDefaults.enableMetalFXUpscale },
        row("gameDefaults.enableMetalHUD", .games, "Metal HUD",
            "New games: Metal performance overlay.") { $0.gameDefaults.enableMetalHUD },
        row("gameDefaults.language", .games, "Game language",
            "New games: starting language; Game Default uses the build's language.") { $0.gameDefaults.language },
        row("gameDefaults.renderScale", .games, "Render scale",
            "New games: internal 3D resolution, from 50% to 100% when supported.") { $0.gameDefaults.renderScale },

        // Controllers
        action("controllerStatus", .controllers, "Gamepad",
               "The connected controller and how its buttons map."),
        action("buttonLayout", .controllers, "Button layout", "View the library controls."),
        action("controllerDeadzone", .controllers, "Stick navigation deadzone",
               "Thumbstick threshold for library navigation; does not alter game input."),
        row("gameDefaults.rumble", .controllers, "Rumble",
            "Default controller vibration for new games.") { $0.gameDefaults.rumble },
        row("gameDefaults.rumbleGain", .controllers, "Rumble strength",
            "Default vibration strength for new games.") { $0.gameDefaults.rumbleGain },

        // Library
        action("gameFolder", .library, "Game ROMs folder", "Where NX Library looks for game sources."),
        action("libraryFolder", .library, "App library folder", "An additional folder to discover built Mac apps."),
        action("importBuilds", .library, "Existing builds",
               "Adds games you already built to the library."),
        action("libraryRefresh", .library, "Library refresh", "Rescan the app folders."),
        row("notifyPortingEnds", .library, "Notify when a porting ends",
            "A notification when a porting finishes while NX Library is in the background.") { $0.notifyPortingEnds },

        // Storage
        action("storageUsage", .storage, "Storage usage", "Recalculate apps, caches, logs and free space."),
        action("buildCaches", .storage, "Build caches", "Delete extracted build caches after the active porting."),
        action("logs", .storage, "Logs", "Delete build and launch logs after confirmation."),
        action("metadataCache", .storage, "Metadata cache", "Clear cached store descriptions and links."),
        action("artworkCache", .storage, "Artwork cache", "Clear downloaded images; manual picks are kept."),
        action("saveBackups", .storage, "Save backups", "Open the folder of verified per-game backups."),
        action("console", .storage, "Console", "View, search and copy logs."),

        // Engine
        action("engineFolder", .engine, "Engine repository", "The upstream checkout used for porting; updates stay manual."),
        action("engineStatus", .engine, "Compatibility", "Engine commit, Metal compiler, toolchain gate and required flags."),
        action("toolchainOverride", .engine, "Untested toolchain override", "Explicitly allow unverified new portings."),
        action("upstream", .engine, "Upstream", "Check newer engine commits without installing them."),
        action("compare", .engine, "Compare", "Open the commit comparison on GitHub."),
        action("keys", .engine, "prod.keys", "Import, replace or detect private keys."),
        action("setup", .startUp, "Setup", "Open the setup checklist."),
        action("environment", .startUp, "Environment", "Re-check the environment and build requirements."),
        action("diagnostics", .about, "Copy diagnostics", "Copy a scrubbed support report."),
        action("appUpdates", .about, "App updates", "Check now, update or read release notes."),
        action("projectDocs", .about, "Open project docs", "Open the project documentation."),
    ]

    public static func changed(in settings: AppSettings, externalChanges: Set<String> = []) -> [SettingDescriptor] {
        all.filter { $0.isChanged(settings) || externalChanges.contains($0.id) }
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
