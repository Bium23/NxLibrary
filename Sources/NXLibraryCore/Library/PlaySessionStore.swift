import Foundation
import Combine

public final class PlaySessionStore: ObservableObject, PlayHistory {
    /// Recent sessions, at most `maxSessions` (running sessions are never dropped).
    @Published public private(set) var sessions: [PlaySession] = []
    /// Play time and last start of sessions trimmed from `sessions`, per game,
    /// so totals and last-played survive trimming.
    @Published public private(set) var carried: [UUID: CarriedPlaytime] = [:]
    /// Another launcher's own total for a game (Steam's), with when it was seen. Not persisted here.
    @Published public private(set) var external: [UUID: ExternalPlaytime] = [:]
    /// When each game's external value was seen, kept while its total is hidden (source off, another
    /// account, launch), so trimming still keeps the part after it.
    public private(set) var trimReferences: [UUID: Date] = [:]
    public static let maxSessions = 200
    /// Each game whose session just started (not a duplicate start).
    public let starts = PassthroughSubject<UUID, Never>()
    public private(set) var loadError: String?

    /// Recent sessions, a bare `[PlaySession]` array as in every earlier version,
    /// so the released app and a development build can share it.
    public let fileURL: URL
    /// Per-game carried totals, beside `fileURL` (`play-sessions-totals.json`).
    public var totalsURL: URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent + "-totals.json")
    }
    private let fileManager: FileManager
    private let now: () -> Date

    public init(fileURL: URL = PlaySessionStore.defaultURL(),
                fileManager: FileManager = .default,
                now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.now = now
        load()
    }

    public static func defaultURL() -> URL {
        AppData.supportRoot.appendingPathComponent("play-sessions.json")
    }

    /// A session for a game of any integration. `sourceID` is the source's identity (a Switch title ID, or a
    /// qualified one such as "steam-570", never a made-up Nintendo title ID); `bundleID` is the app that runs it, when
    /// there is one. A restart closes an open session at its last heartbeat. A game found already running when its
    /// owner starts watching is not a new start: `announces: false` keeps it off `starts`.
    @discardableResult
    public func start(gameID: UUID, sourceID: String, bundleID: String? = nil, announces: Bool = true) -> Bool {
        if isRunning(gameID: gameID) { return false }
        let date = now()
        sessions.append(PlaySession(gameID: gameID, titleID: sourceID, bundleID: bundleID,
                                    startedAt: date, lastHeartbeatAt: date))
        let folded = trim()
        save(totals: folded)
        if announces { starts.send(gameID) }
        return true
    }

    public func heartbeat(for gameID: UUID) {
        guard let index = sessions.lastIndex(where: { $0.gameID == gameID && $0.isActive }) else { return }
        sessions[index].lastHeartbeatAt = now()
        save()
    }

    /// Ends the game's running sessions and returns them, ended.
    @discardableResult
    public func end(gameID: UUID) -> [PlaySession] {
        let date = now()
        var ended: [PlaySession] = []
        for index in sessions.indices where sessions[index].gameID == gameID && sessions[index].isActive {
            sessions[index].endedAt = date
            sessions[index].lastHeartbeatAt = date
            ended.append(sessions[index])
        }
        if !ended.isEmpty { save() }
        return ended
    }

    /// Ends the game's running sessions and returns them, ended.
    @discardableResult
    public func end(bundleID: String?) -> [PlaySession] {
        guard let bundleID else { return [] }
        let date = now()
        var ended: [PlaySession] = []
        for index in sessions.indices
        where sessions[index].bundleID == bundleID && sessions[index].isActive {
            sessions[index].endedAt = date
            sessions[index].lastHeartbeatAt = date
            ended.append(sessions[index])
        }
        if !ended.isEmpty { save() }
        return ended
    }

    public func reconcile(runningBundleIDs: Set<String>) {
        let date = now()
        var changed = false
        for index in sessions.indices where sessions[index].isActive {
            if let bundleID = sessions[index].bundleID,
               runningBundleIDs.contains(bundleID) {
                sessions[index].lastHeartbeatAt = date
                changed = true
            } else {
                sessions[index].endedAt = sessions[index].lastHeartbeatAt
                changed = true
            }
        }
        if changed { save() }
    }

    /// Sets the external totals; publishes only a change.
    public func setExternal(_ values: [UUID: ExternalPlaytime]) {
        if values != external { external = values }
    }

    public func setTrimReferences(_ values: [UUID: Date]) { trimReferences = values }

    /// With an external total: that total plus the part of this store's sessions after it was seen
    /// (it already counts what came before), including trimmed sessions' part after that same value.
    /// Without one: carried time plus every session.
    public func totalDuration(for gameID: UUID) -> TimeInterval {
        totalDuration(for: gameID, with: external[gameID])
    }

    /// The total under a given external value (nil: none), whatever is published.
    public func totalDuration(for gameID: UUID, with external: ExternalPlaytime?) -> TimeInterval {
        let date = now()
        let own = sessions.filter { $0.gameID == gameID }
        guard let base = external else {
            return own.reduce(carried[gameID]?.duration ?? 0) { total, session in
                total + max(0, (session.endedAt ?? date).timeIntervalSince(session.startedAt))
            }
        }
        let trimmed = carried[gameID].flatMap { $0.externalSince == base.since ? $0.afterExternal : nil } ?? 0
        return own.reduce(base.duration + trimmed) { total, session in
            let end = min(session.endedAt ?? date, date)
            return total + max(0, end.timeIntervalSince(max(session.startedAt, base.since)))
        }
    }

    public func lastPlayed(for gameID: UUID) -> Date? {
        let recent = sessions.filter { $0.gameID == gameID }.map(\.startedAt).max()
        return [recent, carried[gameID]?.lastPlayed, external[gameID]?.lastPlayed].compactMap { $0 }.max()
    }

    public func isRunning(gameID: UUID) -> Bool {
        sessions.contains { $0.gameID == gameID && $0.isActive }
    }

    /// Drops the oldest ended sessions beyond `maxCount`, folding each into `carried`.
    /// Returns whether `carried` changed.
    private func trim(maxCount: Int = PlaySessionStore.maxSessions) -> Bool {
        let excess = sessions.count - maxCount
        guard excess > 0 else { return false }
        let dropped = sessions.filter { !$0.isActive }
            .sorted { $0.startedAt < $1.startedAt }
            .prefix(excess)
        guard !dropped.isEmpty else { return false }
        for session in dropped {
            var entry = carried[session.gameID] ?? CarriedPlaytime(duration: 0, lastPlayed: session.startedAt)
            entry.duration += session.duration ?? 0
            entry.lastPlayed = max(entry.lastPlayed, session.startedAt)
            // The part after an external value was seen is not in that value yet: keep it, tied to that value.
            if let since = external[session.gameID]?.since ?? trimReferences[session.gameID] {
                if entry.externalSince != since { entry.externalSince = since; entry.afterExternal = 0 }
                let end = session.endedAt ?? session.lastHeartbeatAt
                entry.afterExternal += max(0, end.timeIntervalSince(max(session.startedAt, since)))
            }
            carried[session.gameID] = entry
        }
        let droppedIDs = Set(dropped.map(\.id))
        sessions.removeAll { droppedIDs.contains($0.id) }
        return true
    }

    /// Writes the sessions, then (when they changed) the carried totals. A crash in
    /// between can lose the just-folded sessions' time, never count it twice.
    private func save(totals: Bool = false) {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try write(JSONEncoder().encode(sessions), to: fileURL)
            if totals {
                let entries = carried.map { CarriedEntry(gameID: $0.key, playtime: $0.value) }
                    .sorted { $0.gameID.uuidString < $1.gameID.uuidString }
                try write(JSONEncoder().encode(entries), to: totalsURL)
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        let temp = url.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temp)
        } else {
            try fileManager.moveItem(at: temp, to: url)
        }
    }

    private func load() {
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                sessions = try JSONDecoder().decode([PlaySession].self, from: Data(contentsOf: fileURL))
                loadError = nil
            } catch {
                sessions = []
                loadError = error.localizedDescription
            }
        }
        // No totals file: nothing was trimmed since carried totals began.
        guard fileManager.fileExists(atPath: totalsURL.path) else { return }
        do {
            let entries = try JSONDecoder().decode([CarriedEntry].self, from: Data(contentsOf: totalsURL))
            carried = Dictionary(entries.map { ($0.gameID, $0.playtime) },
                                 uniquingKeysWith: { first, _ in first })
        } catch {
            carried = [:]
            loadError = error.localizedDescription
        }
    }
}

/// A game's total as another launcher keeps it, and when Arcane first saw that value.
public struct ExternalPlaytime: Equatable, Sendable {
    public let duration: TimeInterval
    public let lastPlayed: Date?
    public let since: Date

    public init(duration: TimeInterval, lastPlayed: Date?, since: Date) {
        self.duration = duration
        self.lastPlayed = lastPlayed
        self.since = since
    }
}

/// Play time folded out of the recent-session list for one game. `afterExternal` is the part of it after
/// the external value seen at `externalSince` (Steam's), which that value does not count yet.
public struct CarriedPlaytime: Codable, Equatable {
    public var duration: TimeInterval
    public var lastPlayed: Date
    public var externalSince: Date?
    public var afterExternal: TimeInterval

    public init(duration: TimeInterval, lastPlayed: Date, externalSince: Date? = nil, afterExternal: TimeInterval = 0) {
        self.duration = duration
        self.lastPlayed = lastPlayed
        self.externalSince = externalSince
        self.afterExternal = afterExternal
    }

    private enum CodingKeys: String, CodingKey { case duration, lastPlayed, externalSince, afterExternal }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        lastPlayed = try c.decode(Date.self, forKey: .lastPlayed)
        externalSince = try c.decodeIfPresent(Date.self, forKey: .externalSince)
        afterExternal = try c.decodeIfPresent(TimeInterval.self, forKey: .afterExternal) ?? 0
    }
}

private struct CarriedEntry: Codable {
    var gameID: UUID
    var playtime: CarriedPlaytime
}
