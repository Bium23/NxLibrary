import Foundation

/// Steam's total for one game and when Arcane first saw that value. `carry` is time Arcane had
/// already shown beyond Steam's new whole minutes (at most `maximumCarry`), so a rising value never
/// makes the total step back.
public struct SteamPlaytimeBaseline: Codable, Equatable, Sendable {
    public static let maximumCarry: TimeInterval = 60
    public let appID: UInt32
    public let minutes: Int
    public let lastPlayed: Date?
    public let seenAt: Date
    public let carry: TimeInterval
    public init(appID: UInt32, minutes: Int, lastPlayed: Date?, seenAt: Date, carry: TimeInterval = 0) {
        self.appID = appID; self.minutes = minutes; self.lastPlayed = lastPlayed; self.seenAt = seenAt; self.carry = carry
    }

    private enum CodingKeys: String, CodingKey { case appID, minutes, lastPlayed, seenAt, carry }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appID = try c.decode(UInt32.self, forKey: .appID)
        minutes = try c.decode(Int.self, forKey: .minutes)
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)
        seenAt = try c.decode(Date.self, forKey: .seenAt)
        carry = try c.decodeIfPresent(TimeInterval.self, forKey: .carry) ?? 0
    }
}

/// The current account's Steam totals, each with when its value was first seen. Arcane adds only
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

    /// Takes a new reading. `previousTotals` are the totals shown until now, by AppID: when Steam's value
    /// rises, what they showed beyond it (up to a minute) is carried. Returns whether anything changed.
    @discardableResult
    public mutating func apply(_ snapshot: SteamPlaytimeSnapshot, now: Date,
                               previousTotals: [UInt32: TimeInterval] = [:]) -> Bool {
        let previous = snapshot.accountID == accountID ? byAppID : [:]
        var next: [UInt32: SteamPlaytimeBaseline] = [:]
        for (appID, entry) in snapshot.entries {
            let old = previous[appID]
            var seenAt = now, carry: TimeInterval = 0
            if let old, old.minutes == entry.minutes {
                seenAt = old.seenAt; carry = old.carry
            } else if let old, entry.minutes > old.minutes, let shown = previousTotals[appID] {
                carry = min(SteamPlaytimeBaseline.maximumCarry, max(0, shown - TimeInterval(entry.minutes) * 60))
            }
            next[appID] = SteamPlaytimeBaseline(appID: appID, minutes: entry.minutes, lastPlayed: entry.lastPlayed,
                                                seenAt: seenAt, carry: carry)
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

    /// When each catalog Steam game's value was seen, for `PlaySessionStore.setTrimReferences`.
    public func references(for games: [CatalogGame]) -> [UUID: Date] {
        external(for: games).mapValues(\.since)
    }

    /// The catalog's Steam games with a baseline, by game UUID, for `PlaySessionStore.setExternal`.
    public func external(for games: [CatalogGame]) -> [UUID: ExternalPlaytime] {
        var result: [UUID: ExternalPlaytime] = [:]
        for game in games {
            guard let appID = game.steamGame?.appID, let baseline = byAppID[appID] else { continue }
            result[game.id] = ExternalPlaytime(duration: TimeInterval(baseline.minutes) * 60 + baseline.carry,
                                               lastPlayed: baseline.lastPlayed, since: baseline.seenAt)
        }
        return result
    }
}
