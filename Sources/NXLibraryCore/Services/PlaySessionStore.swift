import Foundation
import Combine

public final class PlaySessionStore: ObservableObject, PlayHistory {
    /// Recent sessions, at most `maxSessions` (running sessions are never dropped).
    @Published public private(set) var sessions: [PlaySession] = []
    /// Play time and last start of sessions trimmed from `sessions`, per game,
    /// so totals and last-played survive trimming.
    @Published public private(set) var carried: [UUID: CarriedPlaytime] = [:]
    public static let maxSessions = 200
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

    @discardableResult
    public func start(for game: PortedGame) -> Bool {
        if isRunning(gameID: game.id) { return false }
        let date = now()
        let session = PlaySession(
            gameID: game.id,
            titleID: game.titleId ?? game.uniqueKey,
            bundleID: game.effectiveBundleId,
            startedAt: date,
            lastHeartbeatAt: date
        )
        sessions.append(session)
        let folded = trim()
        save(totals: folded)
        return true
    }

    public func heartbeat(for gameID: UUID) {
        guard let index = sessions.lastIndex(where: { $0.gameID == gameID && $0.isActive }) else { return }
        sessions[index].lastHeartbeatAt = now()
        save()
    }

    public func end(gameID: UUID) {
        let date = now()
        var changed = false
        for index in sessions.indices where sessions[index].gameID == gameID && sessions[index].isActive {
            sessions[index].endedAt = date
            sessions[index].lastHeartbeatAt = date
            changed = true
        }
        if changed { save() }
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

    public func totalDuration(for gameID: UUID) -> TimeInterval {
        let date = now()
        return sessions
            .filter { $0.gameID == gameID }
            .reduce(carried[gameID]?.duration ?? 0) { total, session in
                total + max(0, (session.endedAt ?? date).timeIntervalSince(session.startedAt))
            }
    }

    public func lastPlayed(for gameID: UUID) -> Date? {
        let recent = sessions.filter { $0.gameID == gameID }.map(\.startedAt).max()
        return [recent, carried[gameID]?.lastPlayed].compactMap { $0 }.max()
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

/// Play time folded out of the recent-session list for one game.
public struct CarriedPlaytime: Codable, Equatable {
    public var duration: TimeInterval
    public var lastPlayed: Date

    public init(duration: TimeInterval, lastPlayed: Date) {
        self.duration = duration
        self.lastPlayed = lastPlayed
    }
}

private struct CarriedEntry: Codable {
    var gameID: UUID
    var playtime: CarriedPlaytime
}
