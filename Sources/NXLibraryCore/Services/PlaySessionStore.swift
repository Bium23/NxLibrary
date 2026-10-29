import Foundation
import Combine

public final class PlaySessionStore: ObservableObject, PlayHistory {
    @Published public private(set) var sessions: [PlaySession] = []
    public private(set) var loadError: String?

    public let fileURL: URL
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
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NXLibrary/play-sessions.json")
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
        trim()
        save()
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

    public func end(bundleID: String?) {
        guard let bundleID else { return }
        let date = now()
        var changed = false
        for index in sessions.indices
        where sessions[index].bundleID == bundleID && sessions[index].isActive {
            sessions[index].endedAt = date
            sessions[index].lastHeartbeatAt = date
            changed = true
        }
        if changed { save() }
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
            .reduce(0) { total, session in
                total + max(0, (session.endedAt ?? date).timeIntervalSince(session.startedAt))
            }
    }

    public func lastPlayed(for gameID: UUID) -> Date? {
        sessions.filter { $0.gameID == gameID }.map(\.startedAt).max()
    }

    public func isRunning(gameID: UUID) -> Bool {
        sessions.contains { $0.gameID == gameID && $0.isActive }
    }

    private func trim(maxCount: Int = 200) {
        guard sessions.count > maxCount else { return }
        sessions = Array(sessions.sorted { $0.startedAt > $1.startedAt }.prefix(maxCount))
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(sessions)
            let temp = fileURL.appendingPathExtension("tmp")
            try data.write(to: temp, options: .atomic)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: fileURL)
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            sessions = try JSONDecoder().decode([PlaySession].self, from: data)
            loadError = nil
        } catch {
            sessions = []
            loadError = error.localizedDescription
        }
    }
}
