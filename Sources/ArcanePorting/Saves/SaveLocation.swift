import Foundation
import Darwin
import NXLibraryCore

public enum SaveSlot: String, Codable, CaseIterable, Hashable {
    case account, device, user2, user3, user4, user5, user6, user7, user8, users

    public static let legacyCases: [SaveSlot] = [.account, .device]
    public var isLegacy: Bool { Self.legacyCases.contains(self) }
    public var isDirectory: Bool { self != .users }
    public var fileName: String {
        switch self {
        case .account: return "save"
        case .device: return "save_device"
        case .users: return "save.users"
        default: return "save_" + rawValue
        }
    }
}
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
    /// Historical name: the users component is a regular registry file; the other components are directories.
    public func directory(_ slot: SaveSlot) -> URL { root.appendingPathComponent(slot.fileName) }
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
            reason = "Arcane → Settings → Cloud saves"
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
