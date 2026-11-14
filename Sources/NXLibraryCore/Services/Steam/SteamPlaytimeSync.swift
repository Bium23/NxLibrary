import Foundation

/// Which `localconfig.vdf` was read, and its modification date then.
public struct SteamFileStamp: Equatable, Sendable {
    public let file: URL
    public let modified: Date
    public init(file: URL, modified: Date) { self.file = file; self.modified = modified }
}

/// One look at Steam's files, taken off the main thread.
public enum SteamPlaytimeReading: Equatable, Sendable {
    /// No account has signed in on this Mac, or the account has no `localconfig.vdf`.
    case noAccount
    /// The file has not changed since `known`.
    case unchanged(accountID: UInt32)
    /// A file could not be read or parsed (Steam may be rewriting it); the account when known.
    case failed(accountID: UInt32?)
    case read(SteamPlaytimeSnapshot, SteamFileStamp)

    /// Reads only when the file's modification date moved since `known`.
    public static func take(root: URL, known: SteamFileStamp?) -> Self {
        let account: UInt32
        do {
            guard let found = try SteamPlaytimeReader.accountID(root: root) else { return .noAccount }
            account = found
        } catch { return .failed(accountID: nil) }
        let file = SteamPlaytimeReader.localConfigURL(root: root, account: account)
        guard FileManager.default.fileExists(atPath: file.path) else { return .noAccount }
        guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return .failed(accountID: account) }
        let stamp = SteamFileStamp(file: file, modified: modified)
        if stamp == known { return .unchanged(accountID: account) }
        do { return .read(try SteamPlaytimeReader.read(config: file, account: account), stamp) }
        catch { return .failed(accountID: account) }
    }
}

/// What each reading does to the saved baselines and to the totals shown. A failure keeps the last good
/// totals, unless they belong to another account; only "no account" clears them.
public struct SteamPlaytimeSync: Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        /// Totals for `PlaySessionStore.setExternal`; `save` when the baselines changed.
        case publish([UUID: ExternalPlaytime], save: Bool)
        case clear
    }

    public private(set) var baselines: SteamPlaytimeBaselines
    /// The last file read in full; a failed reading leaves it, so the next one tries again.
    public private(set) var stamp: SteamFileStamp?

    public init(baselines: SteamPlaytimeBaselines) { self.baselines = baselines }

    /// The Steam folder changed: the next reading reads in full.
    public mutating func resetStamp() { stamp = nil }

    /// `shownTotal` is what each game shows now, so a rising Steam value can carry it (`SteamPlaytimeBaseline.carry`).
    public mutating func handle(_ reading: SteamPlaytimeReading, games: [CatalogGame],
                                shownTotal: (UUID) -> TimeInterval, now: Date) -> Result {
        switch reading {
        case .noAccount:
            stamp = nil
            return .clear
        case .unchanged(let account), .failed(let account?):
            guard baselines.accountID == account else { return .clear }
            return .publish(baselines.external(for: games), save: false)
        case .failed(nil):
            return .publish(baselines.external(for: games), save: false)
        case .read(let snapshot, let newStamp):
            var shown: [UInt32: TimeInterval] = [:]
            for game in games { if let appID = game.steamGame?.appID { shown[appID] = shownTotal(game.id) } }
            let changed = baselines.apply(snapshot, now: now, previousTotals: shown)
            stamp = newStamp
            return .publish(baselines.external(for: games), save: changed)
        }
    }
}
