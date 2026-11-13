import Foundation

/// What a Steam game's tile asks for in one layout role. Personal picks always come
/// first. A square then uses the installed app's own icon file, never the portrait
/// cover; other roles have no local default and go to the Steam store art.
public struct SteamArtworkRequest: Equatable {
    public let game: CatalogGame
    public let role: LibraryArtworkRole

    public init(game: CatalogGame, role: LibraryArtworkRole) {
        self.game = game; self.role = role
    }

    public var slot: ArtworkSlot { role.slot }
    public var appID: UInt32? { game.steamGame?.appID }
    /// Distinct per game and role, so a square never shows a cover still loading for the same game.
    public var key: String { "\(game.id.uuidString)|\(role.rawValue)" }

    /// The installed app this game launches, as the rest of the library reads it.
    public var application: CatalogNativeApplication? {
        game.steamGame?.installations.first { $0.availability == .available }?.primaryApplication
    }

    /// A file on this Mac for the role: the player's pick, else (square only) the app's own icon.
    public func localURL(picks: SteamPersonalizationStore) -> URL? {
        if let picked = picks.url(titleID: game.personalizationReference.key, slot: slot),
           FileManager.default.fileExists(atPath: picked.path) { return picked }
        return automaticLocalURL
    }

    /// What the role shows with no pick: the app's own icon for the square, nothing else on this Mac.
    public var automaticLocalURL: URL? {
        guard role == .square, let application else { return nil }
        return Self.bundleIcon(of: application.url)
    }

    /// `CFBundleIconFile` inside the bundle's own Resources folder. A name that points
    /// elsewhere (a path, or a link that leaves the folder) is not followed.
    static func bundleIcon(of app: URL) -> URL? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? InstallationFileSnapshot.read(at: plist, maximumBytes: 1_048_576).data,
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = (info["CFBundleIconFile"] as? String)?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty, !name.hasPrefix("."), name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        let resources = app.appendingPathComponent("Contents/Resources")
        let file = resources.appendingPathComponent(name.hasSuffix(".icns") ? name : name + ".icns")
        let folder = resources.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let resolved = file.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard resolved.path.hasPrefix(folder),
              FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
        return file
    }
}
