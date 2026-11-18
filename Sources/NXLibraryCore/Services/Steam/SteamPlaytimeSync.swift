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
    /// The account the last reading named, so a reading that cannot name one does not bring back
    /// totals already hidden for another account.
    private var lastAccount: UInt32?

    public init(baselines: SteamPlaytimeBaselines) { self.baselines = baselines }

    /// The Steam folder changed: the next reading reads in full.
    public mutating func resetStamp() { stamp = nil }

    /// `shownTotal(game, old)` is the game's total under its old baseline (`PlaySessionStore.totalDuration(for:with:)`),
    /// so a rising Steam value can carry what that baseline showed (`SteamPlaytimeBaseline.carry`), whatever is
    /// published at the moment.
    public mutating func handle(_ reading: SteamPlaytimeReading, games: [CatalogGame],
                                shownTotal: (UUID, ExternalPlaytime) -> TimeInterval, now: Date) -> Result {
        switch reading {
        case .noAccount:
            stamp = nil
            lastAccount = nil
            return .clear
        case .unchanged(let account), .failed(let account?):
            lastAccount = account
            guard baselines.accountID == account else { return .clear }
            return .publish(baselines.external(for: games), save: false)
        case .failed(nil):
            guard lastAccount == nil || lastAccount == baselines.accountID else { return .clear }
            return .publish(baselines.external(for: games), save: false)
        case .read(let snapshot, let newStamp):
            lastAccount = snapshot.accountID
            var shown: [UInt32: TimeInterval] = [:]
            if snapshot.accountID == baselines.accountID {
                let old = baselines.external(for: games)
                for game in games {
                    if let appID = game.steamGame?.appID, let base = old[game.id] { shown[appID] = shownTotal(game.id, base) }
                }
            }
            let changed = baselines.apply(snapshot, now: now, previousTotals: shown)
            stamp = newStamp
            return .publish(baselines.external(for: games), save: changed)
        }
    }
}

/// One read of Steam's files at a time. A request during a read is served by one more read when it
/// finishes; a read whose purpose no longer holds (another Steam folder) is not applied and is read
/// again; after `stop` nothing is applied or read again.
public struct SteamPlaytimeReadQueue: Equatable, Sendable {
    public private(set) var isReading = false
    private var generation = 0
    private var again = false

    public init() {}

    /// The ticket to start a read, or nil while one runs.
    public mutating func request() -> Int? {
        if isReading { again = true; return nil }
        isReading = true
        return generation
    }

    /// A read in progress no longer applies; one more read follows it.
    public mutating func invalidate() {
        generation += 1
        again = isReading
    }

    /// Nothing more is wanted: the read in progress is not applied and no read follows.
    public mutating func stop() {
        generation += 1
        again = false
    }

    /// Whether to apply the finished read's result, and whether to read again.
    public mutating func finish(_ ticket: Int) -> (apply: Bool, readAgain: Bool) {
        isReading = false
        defer { again = false }
        return (ticket == generation, again)
    }
}
