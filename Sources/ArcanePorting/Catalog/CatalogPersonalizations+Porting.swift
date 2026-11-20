import Foundation
import NXLibraryCore

extension CatalogPersonalizations {
    public func nxnativeKey(for game: PortedGame) -> String {
        guard let reference = references[game.id], reference.namespace == .nxnative else { return game.titleId ?? game.uniqueKey }
        return reference.key
    }
}

extension CatalogPersonalizationReference {
    /// nxnative's personal data stays at the launcher's root, where it was before the catalog; every other
    /// integration has its own folder (`integrations/steam`).
    public func supportRoot(in launcherRoot: URL) -> URL {
        namespace == .nxnative ? launcherRoot
            : launcherRoot.appendingPathComponent("integrations/\(namespace.rawValue)", isDirectory: true)
    }
}
