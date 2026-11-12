import Foundation
import Darwin

public enum SaveFailure: LocalizedError, Equatable {
    case invalidTitleID, unsafePath, customSavePath, unreadableConfiguration
    case cloudEnabled(String), running, busy, changed, emptyImport, invalidSnapshot, recoveryRequired, cloudPullPending
    case io(String)
    public var errorDescription: String? {
        switch self {
        case .invalidTitleID: return L10n.text("This game needs a valid title ID to manage saves.")
        case .unsafePath: return L10n.text("This save location contains a link or an unsafe path. Manage it in Finder.")
        case .customSavePath: return L10n.text("This game uses a custom save location. Manage it outside this panel.")
        case .unreadableConfiguration: return L10n.text("The game's save configuration could not be read.")
        case .cloudEnabled(let origin): return L10n.format("Cloud saves are enabled in %@. Turn them off there before importing or restoring.", [String(describing: (origin))])
        case .running: return L10n.text("Close the game before managing its saves. Keep it closed until this operation finishes.")
        case .busy: return L10n.text("A save operation or app installation is in progress for this game.")
        case .changed: return L10n.text("The files changed since the preview. Choose the folder again.")
        case .emptyImport: return L10n.text("Choose a folder containing this game's actual save files.")
        case .invalidSnapshot: return L10n.text("This backup is incomplete, changed, or belongs to another game.")
        case .recoveryRequired: return L10n.text("Save recovery is required before Play. Your backup has been kept.")
        case .cloudPullPending: return L10n.text("A cloud save download did not finish. Play the game once so it can put this Mac's save back, then try again.")
        case .io(let message): return message
        }
    }
}

public enum SaveSlot: String, Codable, CaseIterable, Hashable { case account, device }
public struct SaveContext {
    public let location: SaveLocation
    public let cloudReason: String?
    public func requireWrites() throws {
        if let cloudReason { throw SaveFailure.cloudEnabled(cloudReason) }
    }
}
public struct SaveLocation: Equatable {
    public let titleID: String
    public let root: URL
    public func directory(_ slot: SaveSlot) -> URL { root.appendingPathComponent(slot == .account ? "save" : "save_device") }
    /// nxnative's journal of a cloud-save pull (dm/host/save_sync.c, `<DM_SAVE>.pull`, nxnative e6048dea): while it is
    /// there, the game's next start puts this device's save back, so nothing may replace the save folders first.
    public var cloudPullJournal: URL { root.appendingPathComponent("save.pull") }
    public static func validID(_ value: String) -> Bool {
        value.utf8.count == 16 && value.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }
    public static func resolve(titleID: String, appURL: URL, home: URL, environment: [String: String],
                               gameCloudFolder: String?, libraryCloudFolder: String?) throws -> SaveLocation {
        let context = try inspect(titleID: titleID, appURL: appURL, home: home, environment: environment,
                                  gameCloudFolder: gameCloudFolder, libraryCloudFolder: libraryCloudFolder)
        try context.requireWrites()
        return context.location
    }
    public static func inspect(titleID: String, appURL: URL, home: URL, environment: [String: String],
                               gameCloudFolder: String?, libraryCloudFolder: String?) throws -> SaveContext {
        let location = try defaultLocation(titleID: titleID, home: home)
        var env = environment
        var origins = Dictionary(uniqueKeysWithValues: environment.keys.map { ($0, "the launch environment") })
        for (url, origin) in [(location.root.appendingPathComponent("env.txt"), "the game's env.txt"),
                              (appURL.appendingPathComponent("Contents/Resources/dm/env.txt"), "the app's env.txt")] {
            guard SaveFiles.exists(url) else { continue }
            try SaveFiles.safePath(url)
            guard let data = try? SaveFiles.readRegular(url, limit: 1024 * 1024), let text = String(data: data, encoding: .utf8) else { throw SaveFailure.unreadableConfiguration }
            guard !text.contains("\0"), text.components(separatedBy: "\n").allSatisfy({ $0.utf8.count < 4095 }) else { throw SaveFailure.unreadableConfiguration }
            for (key, value) in text.components(separatedBy: "\n").flatMap({ CheatLocator.envLines($0) }) where env[key] == nil {
                env[key] = value; origins[key] = origin
            }
        }
        if let save = env["DM_SAVE"], URL(fileURLWithPath: save, relativeTo: URL(fileURLWithPath: "/")).standardizedFileURL != location.directory(.account) {
            throw SaveFailure.customSavePath
        }
        var reason: String?
        if let sync = env["DM_SAVE_SYNC"] {
            if !sync.isEmpty && sync != "0" { reason = origins["DM_SAVE_SYNC"] }
        } else if let libraryCloudFolder, !libraryCloudFolder.isEmpty {
            reason = "NX Library → Settings → Games"
        } else if let gameCloudFolder, !gameCloudFolder.isEmpty {
            reason = "the game's Cloud saves settings"
        }
        return SaveContext(location: location, cloudReason: reason)
    }
    public static func defaultLocation(titleID: String, home: URL) throws -> SaveLocation {
        guard validID(titleID) else { throw SaveFailure.invalidTitleID }
        let value = SaveLocation(titleID: titleID.uppercased(), root: home.resolvingSymlinksInPath()
            .appendingPathComponent("Library/Application Support/nxnative/\(titleID.uppercased())"))
        try value.validate()
        return value
    }
    public func validate() throws {
        guard Self.validID(titleID), root.lastPathComponent == titleID else { throw SaveFailure.unsafePath }
        try SaveFiles.safePath(root)
        for slot in SaveSlot.allCases { try SaveFiles.safePath(directory(slot)) }
    }
}

/// Filesystem checks shared by saves; lstat never follows a substituted link.
internal enum SaveFiles {
    static func exists(_ url: URL) -> Bool {
        var s = stat(); return lstat(url.path, &s) == 0
    }
    static func safePath(_ url: URL) throws {
        // Foundation canonicalizes /private/var back to /var. Permit only Apple's
        // system aliases; links anywhere in the user-controlled tree remain refused.
        var path = url.path
        if path == "/var" || path.hasPrefix("/var/") || path == "/tmp" || path.hasPrefix("/tmp/") { path = "/private" + path }
        let standardized = URL(fileURLWithPath: path)
        guard !standardized.pathComponents.contains("..") else { throw SaveFailure.unsafePath }
        var current = URL(fileURLWithPath: "/")
        for component in standardized.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            var s = stat()
            if lstat(current.path, &s) == 0 {
                guard (s.st_mode & S_IFMT) == S_IFDIR || (s.st_mode & S_IFMT) == S_IFREG else { throw SaveFailure.unsafePath }
                if current.path != standardized.path && (s.st_mode & S_IFMT) != S_IFDIR { throw SaveFailure.unsafePath }
            } else if errno != ENOENT { throw SaveFailure.io("Could not inspect the save location.") }
        }
    }
}
