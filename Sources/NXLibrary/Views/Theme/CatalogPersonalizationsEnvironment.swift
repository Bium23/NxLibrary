import SwiftUI
import NXLibraryCore

private struct CatalogPersonalizationsKey: EnvironmentKey {
    static let defaultValue = CatalogPersonalizations.empty
}

extension EnvironmentValues {
    var catalogPersonalizations: CatalogPersonalizations {
        get { self[CatalogPersonalizationsKey.self] }
        set { self[CatalogPersonalizationsKey.self] = newValue }
    }
}
