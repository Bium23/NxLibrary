import Foundation

/// One game's playtime as Steam keeps it for an account: minutes on every computer, and the last start.
public struct SteamPlaytimeEntry: Codable, Equatable, Sendable {
    public let minutes: Int
    public let lastPlayed: Date?
    public init(minutes: Int, lastPlayed: Date?) { self.minutes = minutes; self.lastPlayed = lastPlayed }
}

/// The current account's playtime, by AppID.
public struct SteamPlaytimeSnapshot: Equatable, Sendable {
    public let accountID: UInt32
    public let entries: [UInt32: SteamPlaytimeEntry]
    public init(accountID: UInt32, entries: [UInt32: SteamPlaytimeEntry]) { self.accountID = accountID; self.entries = entries }
}

/// Reads Steam's own playtime from `userdata/<account>/config/localconfig.vdf`. Only `Playtime` and
/// `LastPlayed` under `UserLocalConfigStore › Software › Valve › Steam › apps` leave this type: the file
/// also holds app tickets and other private blocks, which are parsed in passing and never kept.
/// Nothing is written to Steam.
public enum SteamPlaytimeReader {
    static let maximumBytes = 8 * 1024 * 1024
    private static let steamID64Base: UInt64 = 76_561_197_960_265_728

    /// The account signed in most recently on this Mac, or nil when none has.
    /// An unreadable `loginusers.vdf` throws: Steam may be rewriting it, which is not "no account".
    public static func accountID(root: URL) throws -> UInt32? {
        let users = root.appendingPathComponent("config/loginusers.vdf")
        guard FileManager.default.fileExists(atPath: users.path) else { return nil }
        return try accountID(loginUsers: text(at: users))
    }

    public static func localConfigURL(root: URL, account: UInt32) -> URL {
        root.appendingPathComponent("userdata/\(account)/config/localconfig.vdf")
    }

    /// The current account's `localconfig.vdf`, or nil when no account has signed in on this Mac.
    public static func localConfigURL(root: URL) throws -> URL? {
        try accountID(root: root).map { localConfigURL(root: root, account: $0) }
    }

    /// Nil without an account or its file; throws when a file cannot be read or parsed.
    public static func read(root: URL) throws -> SteamPlaytimeSnapshot? {
        guard let account = try accountID(root: root) else { return nil }
        let config = localConfigURL(root: root, account: account)
        guard FileManager.default.fileExists(atPath: config.path) else { return nil }
        return try read(config: config, account: account)
    }

    public static func read(config: URL, account: UInt32) throws -> SteamPlaytimeSnapshot {
        SteamPlaytimeSnapshot(accountID: account, entries: try entries(localConfig: text(at: config)))
    }

    /// The account marked `MostRecent`, else the latest `timestamp`.
    public static func accountID(loginUsers text: String) throws -> UInt32? {
        guard case .object(let users)? = try KeyValuesDocument(text: text).uniqueValue(for: "users") else { return nil }
        var best: (account: UInt32, recent: Bool, timestamp: Int)?
        for user in users {
            guard case .object(let fields) = user.value, let id = UInt64(user.key), id >= steamID64Base,
                  let account = UInt32(exactly: id - steamID64Base) else { continue }
            let recent = (try? string("MostRecent", in: fields)) == "1"
            let timestamp = (try? string("timestamp", in: fields)).flatMap { Int($0) } ?? 0
            if let current = best, current.recent != recent ? current.recent : current.timestamp >= timestamp { continue }
            best = (account, recent, timestamp)
        }
        return best?.account
    }

    /// Every app with a numeric `Playtime`; a `LastPlayed` of 0 or none is no date. A file without its
    /// root (empty, or mid-rewrite) throws; an account that never played anything has no entries.
    /// The file only holds data, so `#` keys are ordinary keys, and a repeated block on the path is
    /// read from its first copy: nothing outside the two fields can fail the read.
    public static func entries(localConfig text: String) throws -> [UInt32: SteamPlaytimeEntry] {
        let document = try KeyValuesDocument(text: text, maximumEntries: 500_000, rejectsDirectives: false)
        guard var node = first("UserLocalConfigStore", in: document.entries) else { throw KeyValuesError.malformed }
        for key in ["Software", "Valve", "Steam", "apps"] {
            guard case .object(let children) = node, let child = first(key, in: children) else { return [:] }
            node = child
        }
        guard case .object(let apps) = node else { return [:] }
        var result: [UInt32: SteamPlaytimeEntry] = [:]
        for app in apps {
            guard let appID = UInt32(app.key), appID > 0, case .object(let fields) = app.value,
                  let minutes = (try? string("Playtime", in: fields)).flatMap({ Int($0) }), minutes >= 0 else { continue }
            let seconds = (try? string("LastPlayed", in: fields)).flatMap { TimeInterval($0) } ?? 0
            result[appID] = SteamPlaytimeEntry(minutes: minutes,
                                               lastPlayed: seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil)
        }
        return result
    }

    private static func first(_ key: String, in entries: [KeyValuesEntry]) -> KeyValuesValue? {
        entries.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    private static func string(_ key: String, in fields: [KeyValuesEntry]) throws -> String? {
        guard case .string(let value)? = try fields.uniqueValue(for: key) else { return nil }
        return value
    }

    private static func text(at url: URL) throws -> String {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else { throw KeyValuesError.limitExceeded }
        guard let text = String(data: try Data(contentsOf: url), encoding: .utf8) else { throw KeyValuesError.malformed }
        return text
    }
}
