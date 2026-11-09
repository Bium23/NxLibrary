import Foundation

/// nxnative's cloud saves (engine af616f5+, docs/settings.md "Cloud saves"): a game's
/// Mac and iPhone apps share one save through a folder in iCloud Drive. NX Library
/// is the front end that chooses the folder for its whole library, through the key
/// the engine's Mac launcher reads at every start (docs/frontends.md).
public enum CloudSaves: Codable, Equatable {
    case off
    /// iCloud Drive › nxnative Saves, the folder the engine names `icloud`.
    case iCloudDrive
    /// A folder the player picked (absolute path).
    case folder(String)

    /// The key in each game's preferences domain (`org.nxnative.<title id>`).
    public static let preferenceKey = "cloudSaves.folder"

    /// iCloud Drive's root on this Mac.
    public static func iCloudDriveRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    }

    /// The folder this choice syncs through, nil when off.
    public func folderURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        switch self {
        case .off: return nil
        case .iCloudDrive: return Self.iCloudDriveRoot(home: home).appendingPathComponent("nxnative Saves")
        case .folder(let path): return path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
    }

    public var title: String {
        switch self {
        case .off: return L10n.text("Off")
        case .iCloudDrive: return L10n.text("iCloud Drive")
        case .folder: return L10n.text("Folder")
        }
    }

    /// Left/Right order: Off, iCloud Drive, then the picked folder when there is one.
    public func stepped(_ step: Int, picked: String?) -> CloudSaves {
        var options: [CloudSaves] = [.off, .iCloudDrive]
        if let picked, !picked.isEmpty { options.append(.folder(picked)) }
        let index = options.firstIndex(of: self) ?? 0
        return options[(index + step % options.count + options.count) % options.count]
    }
}
