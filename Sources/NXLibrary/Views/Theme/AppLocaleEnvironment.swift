import SwiftUI
import NXLibraryCore

private struct AppLocaleEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppLocale(language: .english, region: "US")
}

extension EnvironmentValues {
    /// Declares a view's dependency on app-language changes without replacing its identity or state.
    var nxAppLocale: AppLocale {
        get { self[AppLocaleEnvironmentKey.self] }
        set { self[AppLocaleEnvironmentKey.self] = newValue }
    }
}
