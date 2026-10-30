import Foundation

/// One wallpaper file. `id` is "<theme>/<file name without extension>".
public struct Wallpaper: Equatable, Identifiable {
    public let id: String
    public let theme: String
    public let url: URL

    /// "Gruvbox · Flower basket" from "gruvbox/2-flower-basket".
    public var title: String {
        let name = url.deletingPathExtension().lastPathComponent
        let words = name.split(separator: "-").drop { $0.allSatisfy(\.isNumber) }.joined(separator: " ")
        let themeName = theme == WallpaperCatalog.custom
            ? "Your own" : theme.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        return words.isEmpty ? themeName : "\(themeName) · \(words.prefix(1).uppercased())\(words.dropFirst())"
    }
}

/// Wallpapers from the bundle and from Selene imports. `wallpaperID` in settings:
/// nil follows the theme (its first wallpaper), "none" shows none, anything else names one.
public enum WallpaperCatalog {
    public static let none = "none"
    /// The folder (theme) the player's own wallpapers are copied into.
    public static let custom = "custom"
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp"]

    /// Later roots override earlier ones for the same id. Sorted by id.
    public static func scan(roots: [URL], fileManager: FileManager = .default) -> [Wallpaper] {
        var byID: [String: Wallpaper] = [:]
        for root in roots {
            let themes = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles])) ?? []
            for folder in themes {
                let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
                for file in files where imageExtensions.contains(file.pathExtension.lowercased()) {
                    let theme = folder.lastPathComponent
                    let id = "\(theme)/\(file.deletingPathExtension().lastPathComponent)"
                    byID[id] = Wallpaper(id: id, theme: theme, url: file)
                }
            }
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    /// A file name for a wallpaper the player adds: lower case, dashes for
    /// anything else, numbered past `existing` (names without extension).
    public static func customFileName(for original: String, existing: Set<String>) -> String {
        let url = URL(fileURLWithPath: original)
        let ext = url.pathExtension.lowercased()
        let words = url.deletingPathExtension().lastPathComponent.lowercased()
            .split { !($0.isLetter || $0.isNumber) }.joined(separator: "-")
        let base = words.isEmpty ? "wallpaper" : words
        var name = base
        var number = 2
        while existing.contains(name) {
            name = "\(base)-\(number)"
            number += 1
        }
        return ext.isEmpty ? name : "\(name).\(ext)"
    }

    /// The wallpaper to draw for a setting and palette, or nil for none.
    public static func resolve(_ wallpaperID: String?, themeID: String, in wallpapers: [Wallpaper]) -> Wallpaper? {
        switch wallpaperID {
        case none?:
            return nil
        case let id?:
            return wallpapers.first { $0.id == id }
        case nil:
            return wallpapers.first { $0.theme == themeID }
        }
    }
}
