import Foundation
import NXLibraryCore

/// Steam's own playtime for the catalog's Steam games, handed to `PlaySessionStore` as external totals.
/// Steam's file is read off the main thread (`SteamPlaytimeReading.take`) when the catalog or its sources
/// change, when NX Library becomes active and after a Steam session ends, and parsed only when its
/// modification date moved. `SteamPlaytimeReadQueue` keeps one read at a time; `SteamPlaytimeSync` decides
/// what each reading does. Baselines are written off the main thread, in order. Steam's files are never written.
@MainActor
final class SteamPlaytimeCoordinator {
    static let shared = SteamPlaytimeCoordinator()

    private var sessions: PlaySessionStore?
    private var games: [CatalogGame] = []
    private var root: URL?
    private var sync = SteamPlaytimeSync(baselines: SteamPlaytimeBaselines(
        fileURL: AppData.supportRoot.appendingPathComponent("integrations/steam/playtime-baselines.json")))
    private var queue = SteamPlaytimeReadQueue()
    private let saving = DispatchQueue(label: "NXLibrary.SteamPlaytime.save", qos: .utility)
    private var followUp: Task<Void, Never>?

    /// Before any Steam session can start, so trimming already knows each game's last value.
    func start(sessions: PlaySessionStore) {
        self.sessions = sessions
        sessions.setTrimReferences(sync.baselines.references(for: games))
        refresh()
    }

    func stop() {
        sessions = nil
        queue.stop()
        followUp?.cancel(); followUp = nil
    }

    /// Steam games only, and the Steam source's folder while it is enabled.
    func setGames(_ all: [CatalogGame], sources: [CatalogSourceConfiguration]) {
        games = all.filter { $0.integration == .steam }
        let folder = sources.first { $0.integration == .steam && $0.isEnabled }?.rootURL
        if folder != root {
            root = folder
            sync.resetStamp()
            queue.invalidate()
        }
        sessions?.setTrimReferences(sync.baselines.references(for: games))
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
        guard let ticket = queue.request() else { return }
        let known = sync.stamp
        Task.detached(priority: .utility) {
            let result = SteamPlaytimeReading.take(root: root, known: known)
            await MainActor.run { [weak self] in self?.finish(result, ticket: ticket) }
        }
    }

    private func finish(_ result: SteamPlaytimeReading, ticket: Int) {
        let step = queue.finish(ticket)
        if step.apply, let sessions {
            let outcome = sync.handle(result, games: games, shownTotal: { sessions.totalDuration(for: $0, with: $1) }, now: Date())
            switch outcome {
            case .clear:
                sessions.setExternal([:])
            case .publish(let totals, let save):
                if save {
                    let baselines = sync.baselines
                    saving.async { try? baselines.save() }
                }
                sessions.setExternal(totals)
            }
            sessions.setTrimReferences(sync.baselines.references(for: games))
        }
        if step.readAgain { refresh() }
    }
}
