import Foundation
import NXLibraryCore

/// Steam's own playtime for the catalog's Steam games (`SteamPlaytimeReader`, `SteamPlaytimeBaselines`),
/// handed to `PlaySessionStore` as external totals. Steam's file is read off the main thread when the
/// catalog or its sources change, when NX Library becomes active and after a Steam session ends, and
/// only when its modification date moved. A failed read keeps the last good totals. Steam's files are
/// never written.
@MainActor
final class SteamPlaytimeCoordinator {
    static let shared = SteamPlaytimeCoordinator()

    private struct Stamp: Equatable, Sendable { let file: URL; let modified: Date }
    private enum Reading: Sendable { case unchanged, none, failed, read(SteamPlaytimeSnapshot, Stamp) }

    private var sessions: PlaySessionStore?
    private var games: [CatalogGame] = []
    private var root: URL?
    private var baselines = SteamPlaytimeBaselines(
        fileURL: AppData.supportRoot.appendingPathComponent("integrations/steam/playtime-baselines.json"))
    private var lastRead: Stamp?
    private var generation = 0
    private var followUp: Task<Void, Never>?

    func start(sessions: PlaySessionStore) {
        self.sessions = sessions
        refresh()
    }

    func stop() {
        sessions = nil
        generation += 1
        followUp?.cancel(); followUp = nil
    }

    /// Steam games only, and the Steam source's folder while it is enabled.
    func setGames(_ all: [CatalogGame], sources: [CatalogSourceConfiguration]) {
        games = all.filter { $0.integration == .steam }
        let source = sources.first { $0.integration == .steam && $0.isEnabled }
        if source?.rootURL != root { lastRead = nil }
        root = source?.rootURL
        refresh()
    }

    /// Steam may write its new total as the game quits or a little later: read now and once more in a minute.
    func sessionEnded() {
        refresh()
        followUp?.cancel()
        followUp = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func refresh() {
        guard let sessions else { return }
        generation += 1
        guard let root else {
            sessions.setExternal([:])
            return
        }
        let ticket = generation
        let known = lastRead
        Task.detached(priority: .utility) {
            let reading = Self.read(root: root, known: known)
            await MainActor.run { [weak self] in self?.finish(reading, ticket: ticket) }
        }
    }

    private nonisolated static func read(root: URL, known: Stamp?) -> Reading {
        guard let file = SteamPlaytimeReader.localConfigURL(root: root),
              let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return .none }
        let stamp = Stamp(file: file, modified: modified)
        if stamp == known { return .unchanged }
        do {
            guard let snapshot = try SteamPlaytimeReader.read(root: root) else { return .none }
            return .read(snapshot, stamp)
        } catch {
            return .failed
        }
    }

    private func finish(_ reading: Reading, ticket: Int) {
        guard ticket == generation, let sessions else { return }
        switch reading {
        case .none:
            lastRead = nil
            sessions.setExternal([:])
            return
        case .read(let snapshot, let stamp):
            if baselines.apply(snapshot, now: Date()) { try? baselines.save() }
            lastRead = stamp
        case .unchanged, .failed:
            // A file Steam is rewriting may not parse: the last good totals stay, and the next refresh tries again.
            break
        }
        sessions.setExternal(baselines.external(for: games))
    }
}
