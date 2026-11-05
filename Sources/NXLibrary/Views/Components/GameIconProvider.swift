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

    private static let artCache = NSCache<NSString, NSImage>()

    /// The app's icon changed (`AppIconWriter`): read it again.
    public static func forget(_ game: PortedGame) {
        cache.removeObject(forKey: game.uniqueKey as NSString)
        artCache.removeObject(forKey: game.uniqueKey as NSString)
    }

    /// The game's own square icon art, full bleed: the built app's icon file
    /// (what Finder and the Dock show), else the icon nxnative extracted into
    /// the workspace. Nil when neither exists.
    public static func squareArt(for game: PortedGame) -> NSImage? {
        let key = game.uniqueKey as NSString
        if let cached = artCache.object(forKey: key) { return cached }

        var image: NSImage?
        let appURL = game.url
        if appURL.pathExtension.lowercased() == "app", let bundle = Bundle(url: appURL) {
            let name = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String ?? "AppIcon"
            let file = (name as NSString).pathExtension.isEmpty ? name + ".icns" : name
            image = NSImage(contentsOf: appURL.appendingPathComponent("Contents/Resources/\(file)"))
        }
        if image == nil, let workspace = game.workspacePath, let titleId = game.titleId, !titleId.isEmpty {
            image = NSImage(contentsOf: URL(fileURLWithPath: workspace)
                .appendingPathComponent("\(titleId)_build/extract/v0/icon.jpg"))
        }
        if let image { artCache.setObject(image, forKey: key) }
        return image
    }
}
