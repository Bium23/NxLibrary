import Foundation

/// What Reset group puts back in `AppSettings`, one section at a time. Preferences outside
/// `AppSettings` (theme applied, app icon, stick deadzone, game apps folder) are reset by the
/// Settings screen beside this; cloud saves and credentials are never reset.
public enum SettingsReset {
    public static func canReset(_ section: SettingsSection) -> Bool {
        switch section {
        case .startUp, .navigation, .spotlight, .soundMusic, .look, .controllers, .libraryGames, .library, .games:
            return true
        case .search, .changed, .apiServices, .sources, .storage, .engine, .keys, .cloudSaves, .portingStorage,
             .about, .console:
            return false
        }
    }

    /// `settings` with the section's values back at their defaults; everything else unchanged.
    public static func reset(_ section: SettingsSection, in settings: AppSettings) -> AppSettings {
        let defaults = AppSettings()
        var next = settings
        switch section {
        case .startUp:
            next.appLanguage = defaults.appLanguage
            next.appRegion = defaults.appRegion
            next.startOn = defaults.startOn
            next.restoreLastGame = defaults.restoreLastGame
            next.startInFullscreen = defaults.startInFullscreen
            next.checkAppUpdatesAtLaunch = defaults.checkAppUpdatesAtLaunch
            next.introAnimation = defaults.introAnimation
        case .navigation:
            next.showButtonHints = defaults.showButtonHints
            next.buttonNames = defaults.buttonNames
            next.viewButtonSwitches = defaults.viewButtonSwitches
        case .spotlight:
            next.visibleSpotlightCards = defaults.visibleSpotlightCards
            next.startingTab = defaults.startingTab
            next.spotlightOrder = defaults.spotlightOrder
        case .soundMusic:
            next.interfaceSounds = defaults.interfaceSounds
            next.soundVolume = defaults.soundVolume
            next.quietLaunch = defaults.quietLaunch
        case .look:
            next.colorThemeID = defaults.colorThemeID
            next.wallpaperID = defaults.wallpaperID
            next.settingsWallpaperID = defaults.settingsWallpaperID
            next.keepWallpaperOnGames = defaults.keepWallpaperOnGames
            next.backgroundSizing = defaults.backgroundSizing
            next.wallpaperBrightness = defaults.wallpaperBrightness
            next.backgroundShade = defaults.backgroundShade
            next.readableText = defaults.readableText
            next.animatedBackground = defaults.animatedBackground
            next.particleStyle = defaults.particleStyle
            next.showClock = defaults.showClock
            next.reduceMotion = defaults.reduceMotion
        case .libraryGames:
            next.launchStyle = defaults.launchStyle
            next.launchMotion = defaults.launchMotion
            next.launchShade = defaults.launchShade
            next.showsSessionCard = defaults.showsSessionCard
            next.surprisePool = defaults.surprisePool
        case .games:
            next.gameDefaults = defaults.gameDefaults
        case .library:
            next.refreshLibraryAtLaunch = defaults.refreshLibraryAtLaunch
            next.notifyPortingEnds = defaults.notifyPortingEnds
        case .controllers, .search, .changed, .apiServices, .sources, .storage, .engine, .keys, .cloudSaves,
             .portingStorage, .about, .console:
            break
        }
        return next
    }
}
