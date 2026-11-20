import Foundation

/// One Steam achievement as this Mac's Steam cache knows it, for the current account.
public struct SteamAchievement: Equatable, Sendable {
    /// Steam's API name (`ACH_0039`), the key for its rarity.
    public let apiName: String
    public let name: String
    public let description: String
    public let hidden: Bool
    /// File names on Steam's CDN (`<hash>.jpg`), color and gray.
    public let icon: String?
    public let grayIcon: String?
    public let unlockedAt: Date?

    public init(apiName: String, name: String, description: String, hidden: Bool, icon: String?, grayIcon: String?, unlockedAt: Date?) {
        self.apiName = apiName; self.name = name; self.description = description; self.hidden = hidden
        self.icon = icon; self.grayIcon = grayIcon; self.unlockedAt = unlockedAt
    }
}

/// Reads a game's achievements from Steam's cache in `appcache/stats`: the schema (`UserGameStatsSchema_<AppID>.bin`:
/// names and descriptions in every language, hidden, icons) and the current account's stats
/// (`UserGameStats_<account>_<AppID>.bin`), of which only `AchievementTimes` is read. Nothing is written, logged
/// or kept beyond the returned values. The format is Valve's and undocumented: anything unexpected throws.
public enum SteamAchievementReader {
    public static func schemaURL(root: URL, appID: UInt32) -> URL {
        root.appendingPathComponent("appcache/stats/UserGameStatsSchema_\(appID).bin")
    }

    public static func statsURL(root: URL, account: UInt32, appID: UInt32) -> URL {
        root.appendingPathComponent("appcache/stats/UserGameStats_\(account)_\(appID).bin")
    }

    /// The game's achievements, or nil when there is no schema, no signed-in account, or no stats file for that
    /// account (it never loaded this game's stats here: the numbers would be wrong). Throws on unreadable files.
    public static func read(root: URL, appID: UInt32, language: String) throws -> [SteamAchievement]? {
        let schema = schemaURL(root: root, appID: appID)
        guard FileManager.default.fileExists(atPath: schema.path),
              let account = try SteamPlaytimeReader.accountID(root: root) else { return nil }
        let stats = statsURL(root: root, account: account, appID: appID)
        guard FileManager.default.fileExists(atPath: stats.path) else { return nil }
        return try achievements(schema: SteamBinaryKeyValues.parse(data(at: schema)),
                                stats: SteamBinaryKeyValues.parse(data(at: stats)), appID: appID, language: language)
    }

    static func achievements(schema: [KeyValuesEntry], stats: [KeyValuesEntry], appID: UInt32, language: String) throws -> [SteamAchievement] {
        let times = unlockTimes(stats)
        guard let game = schema.firstObject(for: "\(appID)"), let statList = game.firstObject(for: "stats") else { return [] }
        var result: [(stat: Int, bit: Int, achievement: SteamAchievement)] = []
        for stat in statList {
            guard case .object(let statFields) = stat.value, let bits = statFields.firstObject(for: "bits"),
                  let statNumber = Int(stat.key) else { continue }
            for bit in bits {
                guard case .object(let fields) = bit.value, let bitNumber = Int(bit.key),
                      let api = fields.firstString(for: "name") else { continue }
                let display = fields.firstObject(for: "display") ?? []
                let names = display.firstObject(for: "name") ?? []
                let descs = display.firstObject(for: "desc") ?? []
                let seconds = times[stat.key]?[bit.key].flatMap { Int64($0) } ?? 0
                result.append((statNumber, bitNumber, SteamAchievement(
                    apiName: api,
                    name: localized(names, language) ?? api,
                    description: localized(descs, language) ?? "",
                    hidden: display.firstString(for: "hidden") == "1",
                    icon: display.firstString(for: "icon").flatMap { $0.isEmpty ? nil : $0 },
                    grayIcon: display.firstString(for: "icon_gray").flatMap { $0.isEmpty ? nil : $0 },
                    unlockedAt: seconds > 0 ? Date(timeIntervalSince1970: TimeInterval(seconds)) : nil)))
            }
        }
        return result.sorted { ($0.stat, $0.bit) < ($1.stat, $1.bit) }.map(\.achievement)
    }

    /// `cache › <stat> › AchievementTimes › <bit>`; nothing else of the stats file is read.
    private static func unlockTimes(_ stats: [KeyValuesEntry]) -> [String: [String: String]] {
        guard let cache = stats.firstObject(for: "cache") else { return [:] }
        var times: [String: [String: String]] = [:]
        for stat in cache {
            guard case .object(let fields) = stat.value, let list = fields.firstObject(for: "AchievementTimes") else { continue }
            for entry in list { if case .string(let value) = entry.value { times[stat.key, default: [:]][entry.key] = value } }
        }
        return times
    }

    private static func localized(_ entries: [KeyValuesEntry], _ language: String) -> String? {
        for key in [language, "english"] {
            if let text = entries.firstString(for: key), !text.isEmpty { return text }
        }
        return nil
    }

    private static func data(at url: URL) throws -> Data {
        try InstallationFileSnapshot.read(at: url, maximumBytes: SteamBinaryKeyValues.maximumBytes).data
    }
}
