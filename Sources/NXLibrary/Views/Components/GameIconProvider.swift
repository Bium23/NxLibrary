import AppKit
import NXLibraryCore

/// The installed app has the game's icon. Before a build succeeds, use the
/// icon nxnative already extracted into the workspace instead of the generic
/// folder icon.
public enum GameIconProvider {
    private static let cache = NSCache<NSString, NSImage>()

    public static func icon(for game: PortedGame) -> NSImage {
        let key = game.uniqueKey as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let appURL = game.url
        let isApp = appURL.pathExtension.lowercased() == "app"
            && FileManager.default.fileExists(
                atPath: appURL.appendingPathComponent("Contents/Info.plist").path
            )

        if isApp {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            cache.setObject(icon, forKey: key)
            return icon
        }

        if let workspace = game.workspacePath, let titleId = game.titleId, !titleId.isEmpty {
            let extracted = URL(fileURLWithPath: workspace)
                .appendingPathComponent("\(titleId)_build/extract/v0/icon.jpg")
            if let icon = NSImage(contentsOf: extracted) {
                cache.setObject(icon, forKey: key)
                return icon
            }
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}
