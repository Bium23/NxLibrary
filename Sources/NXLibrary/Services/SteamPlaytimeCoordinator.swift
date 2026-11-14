import Foundation
import NXLibraryCore

/// Steam's own playtime for the catalog's Steam games, handed to `PlaySessionStore` as external totals.
/// Steam's file is read off the main thread (`SteamPlaytimeReading.take`) when the catalog or its sources
/// change, when NX Library becomes active and after a Steam session ends, and parsed only when its
/// modification date moved. One read runs at a time: a request during it is served by one more read at
/// the end. What each reading does is `SteamPlaytimeSync`'s rule. Steam's files are never written.
@MainActor
final class SteamPlaytimeCoordinator {
    static let shared = SteamPlaytimeCoordinator()

    private var sessions: PlaySessionStore?
    private var games: [CatalogGame] = []
    private var root: URL?
    private var sync = SteamPlaytimeSync(baselines: SteamPlaytimeBaselines(
        fileURL: AppData.supportRoot.appendingPathComponent("integrations/steam/playtime-baselines.json")))
    /// Bumped when a reading in progress no longer applies (stopped, or another Steam folder).
    private var generation = 0
    private var reading = false
    private var readAgain = false
    private var followUp: Task<Void, Never>?

    func start(sessions: PlaySessionStore) {
        self.sessions = sessions
        refresh()
    }

    func stop() {
        sessions = nil
        generation += 1
        readAgain = false
        followUp?.cancel(); followUp = nil
    }

    /// Steam games only, and the Steam source's folder while it is enabled.
    func setGames(_ all: [CatalogGame], sources: [CatalogSourceConfiguration]) {
        games = all.filter { $0.integration == .steam }
        let folder = sources.first { $0.integration == .steam && $0.isEnabled }?.rootURL
        if folder != root {
            root = folder
            sync.resetStamp()
            generation += 1
        }
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
        guard let root else {
            sessions.setExternal([:])
            return
        }
        if reading { readAgain = true; return }
        reading = true
        let ticket = generation
        let known = sync.stamp
        Task.detached(priority: .utility) {
            let result = SteamPlaytimeReading.take(root: root, known: known)
            await MainActor.run { [weak self] in self?.finish(result, ticket: ticket) }
        }
    }

    private func finish(_ result: SteamPlaytimeReading, ticket: Int) {
        reading = false
        if ticket == generation, let sessions {
            switch sync.handle(result, games: games, shownTotal: sessions.totalDuration(for:), now: Date()) {
            case .clear:
                sessions.setExternal([:])
            case .publish(let totals, let save):
                if save { try? sync.baselines.save() }
                sessions.setExternal(totals)
            }
        } else {
            readAgain = sessions != nil
        }
        if readAgain {
            readAgain = false
            refresh()
        }
    }
}
