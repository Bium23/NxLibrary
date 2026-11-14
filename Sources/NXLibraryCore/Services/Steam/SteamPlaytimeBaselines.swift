import Foundation

/// Steam's total for one game and when NX Library first saw that value.
public struct SteamPlaytimeBaseline: Codable, Equatable, Sendable {
    public let appID: UInt32
    public let minutes: Int
    public let lastPlayed: Date?
    public let seenAt: Date
    public init(appID: UInt32, minutes: Int, lastPlayed: Date?, seenAt: Date) {
        self.appID = appID; self.minutes = minutes; self.lastPlayed = lastPlayed; self.seenAt = seenAt
    }
}

/// The current account's Steam totals, each with when its value was first seen. NX Library adds only
/// its own play after `seenAt`: Steam's value already counts what came before. A new value (up or down)
/// or another account starts over; Steam is the source of truth.
public struct SteamPlaytimeBaselines: Equatable, Sendable {
    public let fileURL: URL
    public private(set) var accountID: UInt32?
    public private(set) var byAppID: [UInt32: SteamPlaytimeBaseline] = [:]

    private struct File: Codable { var accountID: UInt32; var baselines: [SteamPlaytimeBaseline] }

    /// Loads the saved baselines; a missing or broken file means none.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return }
        accountID = file.accountID
        byAppID = Dictionary(file.baselines.map { ($0.appID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Takes a new reading. Returns whether anything changed.
    @discardableResult
    public mutating func apply(_ snapshot: SteamPlaytimeSnapshot, now: Date) -> Bool {
        let previous = snapshot.accountID == accountID ? byAppID : [:]
        var next: [UInt32: SteamPlaytimeBaseline] = [:]
        for (appID, entry) in snapshot.entries {
            let seenAt = previous[appID].flatMap { $0.minutes == entry.minutes ? $0.seenAt : nil } ?? now
            next[appID] = SteamPlaytimeBaseline(appID: appID, minutes: entry.minutes, lastPlayed: entry.lastPlayed, seenAt: seenAt)
        }
        let changed = snapshot.accountID != accountID || next != byAppID
        accountID = snapshot.accountID
        byAppID = next
        return changed
    }

    /// Writes atomically; the directory is created when missing.
    public func save() throws {
        guard let accountID else { return }
        let file = File(accountID: accountID, baselines: byAppID.values.sorted { $0.appID < $1.appID })
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(file).write(to: fileURL, options: .atomic)
    }

    /// The catalog's Steam games with a baseline, by game UUID, for `PlaySessionStore.setExternal`.
    public func external(for games: [CatalogGame]) -> [UUID: ExternalPlaytime] {
        var result: [UUID: ExternalPlaytime] = [:]
        for game in games {
            guard let appID = game.steamGame?.appID, let baseline = byAppID[appID] else { continue }
            result[game.id] = ExternalPlaytime(duration: TimeInterval(baseline.minutes) * 60,
                                               lastPlayed: baseline.lastPlayed, since: baseline.seenAt)
        }
        return result
    }
}
