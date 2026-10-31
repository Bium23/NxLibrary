import Foundation

/// Where a wallpaper chosen in the theme gallery goes, asked once the choice is made.
public enum WallpaperPlacement: CaseIterable, Sendable {
    /// Stays in the gallery; nothing changes.
    case notNow
    case settingsOnly
    /// The app's wallpaper; Settings go back to following it.
    case everywhere

    public static let dialogTitle = "Where should this wallpaper go?"

    public var title: String {
        switch self {
        case .notNow: return "Not now"
        case .settingsOnly: return "Settings only"
        case .everywhere: return "Everywhere"
        }
    }

    /// `wallpaperID` as the gallery gives it: nil is the theme's own, `WallpaperCatalog.none` none.
    public func apply(_ wallpaperID: String?, to settings: inout AppSettings) {
        switch self {
        case .notNow:
            break
        case .settingsOnly:
            settings.settingsWallpaperID = wallpaperID ?? WallpaperCatalog.themeOwn
        case .everywhere:
            settings.wallpaperID = wallpaperID
            settings.settingsWallpaperID = nil
        }
    }
}
