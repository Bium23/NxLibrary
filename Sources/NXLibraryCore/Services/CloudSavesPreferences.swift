import Foundation

/// Writes the library's cloud saves folder into each game's preferences domain,
/// the key nxnative's Mac launcher reads at every start (docs/frontends.md).
public struct CloudSavesPreferences {
    /// Sets (`nil` removes) `cloudSaves.folder` in one domain.
    public var write: (_ path: String?, _ domain: String) -> Void
    public var fileManager: FileManager
    public var home: URL

    public init(write: @escaping (_ path: String?, _ domain: String) -> Void = CloudSavesPreferences.systemWrite,
                fileManager: FileManager = .default,
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.write = write
        self.fileManager = fileManager
        self.home = home
    }

    public static func systemWrite(_ path: String?, _ domain: String) {
        let app = domain as CFString
        CFPreferencesSetValue(CloudSaves.preferenceKey as CFString, path as CFString?, app,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    public enum Failure: LocalizedError, Equatable {
        case iCloudDriveOff
        case folderUnavailable(String)

        public var errorDescription: String? {
            switch self {
            case .iCloudDriveOff:
                return "iCloud Drive is not on for this Mac. Turn it on in System Settings › Apple Account › iCloud, or choose a folder."
            case .folderUnavailable(let path):
                return "Could not use \(path) for cloud saves."
            }
        }
    }

    /// The folder to write, created when missing. Nil for Off.
    public func prepare(_ choice: CloudSaves) throws -> URL? {
        guard let folder = choice.folderURL(home: home) else { return nil }
        if choice == .iCloudDrive,
           !fileManager.fileExists(atPath: CloudSaves.iCloudDriveRoot(home: home).path) {
            throw Failure.iCloudDriveOff
        }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw Failure.folderUnavailable(folder.path)
        }
        return folder
    }

    /// The whole library's choice changed: every game gets the folder, or loses
    /// the key for Off.
    public func apply(_ choice: CloudSaves, to domains: [String]) throws {
        let path = try prepare(choice)?.path
        for domain in Set(domains) { write(path, domain) }
    }

    /// One game is about to start. Off leaves its key alone, so a folder the
    /// player chose in the game's own settings window stays.
    public func applyBeforeLaunch(_ choice: CloudSaves, domain: String) throws {
        guard let path = try prepare(choice)?.path else { return }
        write(path, domain)
    }
}
