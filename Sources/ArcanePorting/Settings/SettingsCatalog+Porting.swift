import Foundation
import NXLibraryCore

/// The rows of the Porting group (Engine, Keys, Library, New games, Cloud saves, Porting storage), and the whole
/// Settings list: the base rows and these, in screen order.
extension SettingsCatalog {
    /// Every Settings row (spec §5.7), in screen order.
    public static let all: [SettingDescriptor] = ordered(baseRows + portingRows)

    public static func changed(in settings: AppSettings, externalChanges: Set<String> = []) -> [SettingDescriptor] {
        changed(in: settings, externalChanges: externalChanges, rows: all)
    }

    /// Case- and diacritic-insensitive match over title and about.
    public static func search(_ query: String) -> [SettingDescriptor] {
        search(query, in: all)
    }

    /// Each Porting section's rows, in screen order.
    static let portingRows: [SettingDescriptor] = [
        // Engine
        row("checkEngineAtLaunch", .engine, "Check engine at launch",
            "Checks the engine and toolchain each time Arcane starts.") { $0.checkEngineAtLaunch },
        action("engineFolder", .engine, "Engine repository", "The upstream checkout used for porting; updates stay manual."),
        action("engineStatus", .engine, "Compatibility", "Engine commit, Metal compiler, build environment, toolchain gate and required flags."),
        action("toolchainOverride", .engine, "Untested toolchain override", "Explicitly allow unverified new portings."),
        action("upstream", .engine, "Upstream", "Check newer engine commits without installing them."),
        action("newestEngine", .engine, "Newest engine", "Build with nxnative main before Arcane has tested it, or go back to the tested engine."),
        action("compare", .engine, "Compare", "Open the commit comparison on GitHub."),
        action("setup", .engine, "Setup", "Open the setup checklist."),

        // Keys
        action("keys", .keys, "prod.keys", "Import, replace or detect private keys."),

        // Library
        row("refreshLibraryAtLaunch", .library, "Refresh library at launch",
            "Scans your library folders for new or removed games at start.") { $0.refreshLibraryAtLaunch },
        action("boxCovers", .library, "Box covers", "Open GameTDB for box covers."),
        action("gameFolder", .library, GameFoldersCopy.sourcesTitle, "Game sources: NSP, XCI, NSZ and XCZ files, or Switch 2 NUP files and extracted folders, for builds. Optional for existing apps."),
        action("libraryFolder", .library, GameFoldersCopy.appsTitle, "Choose where to find existing nxnative game apps and install new builds."),
        action("libraryRefresh", .library, "Scan game apps", "Find existing nxnative builds and refresh the library."),
        row("notifyPortingEnds", .library, "Notify when a porting ends",
            "A notification when a porting finishes while Arcane is in the background.") { $0.notifyPortingEnds },

        // New games
        row("gameDefaults.fullscreen", .games, "Fullscreen",
            "New games: start in fullscreen or a window.") { $0.gameDefaults.fullscreen },
        row("gameDefaults.enable60FPS", .games, "60 FPS",
            "New games: frame-rate target of 30 or 60 FPS.") { $0.gameDefaults.enable60FPS },
        row("gameDefaults.isDockedMode", .games, "Docked mode",
            "New games: console profile or handheld mode.") { $0.gameDefaults.isDockedMode },
        row("gameDefaults.enableMetalFXUpscale", .games, "MetalFX upscaling",
            "New games: MetalFX enlarges the finished picture to your screen.") { $0.gameDefaults.enableMetalFXUpscale },
        row("gameDefaults.enableMetalHUD", .games, "Metal HUD",
            "New games: Metal performance overlay.") { $0.gameDefaults.enableMetalHUD },
        row("gameDefaults.language", .games, "Game language",
            "New games: starting language; Game Default uses the build's language.") { $0.gameDefaults.language },
        row("gameDefaults.renderScale", .games, "Render scale",
            "New games: internal 3D resolution, from 50% to 100% when supported.") { $0.gameDefaults.renderScale },
        row("gameDefaults.rumble", .games, "Rumble",
            "New games: default controller vibration for new ported games.") { $0.gameDefaults.rumble },
        row("gameDefaults.rumbleGain", .games, "Rumble strength",
            "New games: default vibration strength for new ported games.") { $0.gameDefaults.rumbleGain },

        // Cloud saves
        row("cloudSaves", .cloudSaves, "Cloud saves",
            "One sync choice for all games, applied at next launch: Off, iCloud Drive or a folder you choose. Only the primary user and device save sync.") { $0.cloudSaves },
        row("cloudSavesPickedFolder", .cloudSaves, "Cloud saves folder",
            "The chosen folder for save sync; choosing a folder enables it.") { $0.cloudSavesPickedFolder },

        // Porting storage
        action("buildCaches", .portingStorage, "Build caches", "Delete a game's build cache or clear all caches after confirmation; rebuilds may take longer."),
    ]
}
