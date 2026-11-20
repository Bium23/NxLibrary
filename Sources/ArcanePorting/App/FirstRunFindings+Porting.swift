import Foundation
import NXLibraryCore

/// The first launch's count of ported apps: the nxnative apps in the Game apps folder.
extension FirstRunFindings {
    /// Blocking; run it on a worker.
    public static func read(steamRoot: URL, appsFolder: URL, cancelled: @escaping () -> Bool) -> FirstRunFindings {
        read(steamRoot: steamRoot, portedAppCount: { portedApps(in: appsFolder) }, cancelled: cancelled)
    }

    static func portedApps(in appsFolder: URL) -> Int {
        ImportService().scan(directories: [appsFolder]).count
    }
}

extension FirstRunFindingsReader {
    public func start(steamRoot: URL, appsFolder: URL) {
        start(steamRoot: steamRoot, portedAppCount: { FirstRunFindings.portedApps(in: appsFolder) })
    }
}
