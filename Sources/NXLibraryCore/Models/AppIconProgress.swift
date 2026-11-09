import Foundation

/// The icon is prepared separately from the successful game build. Missing artwork is informational.
public enum AppIconProgress: Equatable {
    case searching, updating, updated, launcherOnly, original, unavailable
    case failed(String)

    public var message: String {
        switch self {
        case .searching: return "Looking for an icon…"
        case .updating: return "Updating the app icon in Finder and the Dock… large games can take a minute"
        case .updated: return "App icon updated in Finder and the Dock"
        case .launcherOnly: return "Icon used only in NX Library"
        case .original: return "Using the game's original app icon"
        case .unavailable: return "No icon available. You can choose one."
        case .failed(let reason): return "The app icon was not changed: \(reason)"
        }
    }

    public var buildMessage: String {
        if self == .unavailable { return "Game ready. No icon found; add one in Change artwork." }
        if case .failed = self { return "Game built. \(message)" }
        return "Game ready. \(message)"
    }

    /// Only append to an existing finished engine log. Failure to log must not affect the build or Play.
    public func appendToBuildLog(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n[NX Library · Icon] \(buildMessage)\n".utf8))
    }
}
