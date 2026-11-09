import Foundation

/// The icon is prepared separately from the successful game build. Missing artwork is informational.
public enum AppIconProgress: Equatable {
    case searching, updating, updated, launcherOnly, original, unavailable
    case failed(String)

    public var message: String {
        switch self {
        case .searching: return L10n.text("Looking for an icon…")
        case .updating: return L10n.text("Updating the app icon in Finder and the Dock… large games can take a minute")
        case .updated: return L10n.text("App icon updated in Finder and the Dock")
        case .launcherOnly: return L10n.text("Icon used only in NX Library")
        case .original: return L10n.text("Using the game's original app icon")
        case .unavailable: return L10n.text("No icon available. You can choose one.")
        case .failed(let reason): return L10n.format("The app icon was not changed: %@", [String(describing: (reason))])
        }
    }

    public var buildMessage: String {
        if self == .unavailable { return L10n.text("Game ready. No icon found; add one in Change artwork.") }
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
