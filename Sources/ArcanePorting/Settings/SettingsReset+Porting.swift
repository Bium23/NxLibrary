import Foundation
import NXLibraryCore

extension SettingsReset {
    /// `settings` with the section's values back at their defaults, New games included; everything else unchanged.
    public static func reset(_ section: SettingsSection, in settings: AppSettings) -> AppSettings {
        var next = resetShared(section, in: settings)
        if section == .games { next.gameDefaults = AppSettings().gameDefaults }
        return next
    }
}
