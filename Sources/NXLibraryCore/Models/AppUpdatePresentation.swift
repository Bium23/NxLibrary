import Foundation

public enum AppUpdateState: Equatable {
    case hidden, developer, readOnly, idle, checking, upToDate
    case available(AppUpdate.Release)
    case downloading(Double), verifying, installing
    case failed(String)
}

extension AppUpdate {
    /// A manual release check is safe for development/read-only copies; replacing those copies is not.
    public static func mayInstall(_ release: Release, runningVersion: String, installation: Installability) -> Bool {
        installation == .ok && isNewer(release.version, than: runningVersion)
    }
}
