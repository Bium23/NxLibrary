import Foundation
import Combine
import os

/// One of your games, as the store asks GameBanana about it: the names to match it by, last played first.
public struct ModStoreGame: Equatable, Sendable {
    public let titleID: String
    public let name: String
    public let names: [String]

    public init(titleID: String, name: String, names: [String]) {
        self.titleID = titleID
        self.name = name
        self.names = names
    }
}

/// The mod store's data: every game's mods that work. It opens from the snapshots on disk at once, then refreshes
/// in the background the games whose snapshot is missing or older than `maxAge`, `concurrent` at a time in the order
/// given (last played first), publishing each game once it is complete, so rows change in one step, not tile by
/// tile. A game without a remembered GameBanana page is matched only when the name match is certain; an uncertain
/// one is left to the game's own Mods band, which asks. Requests run only between `open` and `close`.
@MainActor
public final class ModStoreModel: ObservableObject {
    public enum Phase: Equatable {
        case idle
        /// Nothing to show yet; snapshots are read or games are being asked about.
        case loading
        case ready
        /// No connection and nothing saved to show.
        case offline
    }

    @Published public private(set) var games: [ModCatalogGame] = []
    @Published public private(set) var phase: Phase = .idle
    /// Some games are still being asked about (a quiet line on the page).
    @Published public private(set) var refreshing = false

    private static let log = Logger(subsystem: "local.nxlibrary", category: "gamebanana")
    private let client: GameBananaClient
    private let matches: GameBananaMatchStore
    private let snapshots: ModCatalogSnapshots
    private let maxAge: TimeInterval
    private let concurrent: Int
    private let now: @Sendable () -> Date
    private var order: [ModStoreGame] = []
    private var found: [String: [AvailableMod]] = [:]
    private var task: Task<Void, Never>?

    public init(client: GameBananaClient, matches: GameBananaMatchStore, snapshots: ModCatalogSnapshots,
                maxAge: TimeInterval = 6 * 3600, concurrent: Int = 2, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.matches = matches
        self.snapshots = snapshots
        self.maxAge = maxAge
        self.concurrent = max(1, concurrent)
        self.now = now
    }

    /// Shows the store for these games. Opening again for the same games keeps what runs; other games start over.
    public func open(_ games: [ModStoreGame]) {
        let games = games.filter { !$0.titleID.isEmpty }
        if games == order, phase != .idle { return }
        close()
        order = games
        phase = .loading
        refreshing = true
        Self.log.notice("store open \(games.count, privacy: .public) games")
        let snapshots = self.snapshots
        task = Task { [weak self] in
            // Snapshots are read off the main thread: a large library opens without a hitch.
            let saved = await Task.detached(priority: .userInitiated) {
                Dictionary(games.compactMap { game in snapshots.load(titleID: game.titleID).map { (game.titleID, $0) } },
                           uniquingKeysWith: { first, _ in first })
            }.value
            guard let self, !Task.isCancelled else { return }
            // Only a snapshot of the GameBanana game the player has now: another pick, or None of these, hides it.
            let shown = saved.filter { titleID, snapshot in
                if case .game(let id, _, _) = self.matches.choice(titleID: titleID) { return id == snapshot.gameBananaID }
                return false
            }
            for (titleID, snapshot) in shown { self.found[titleID] = snapshot.mods }
            self.publish()
            if !self.games.isEmpty { self.phase = .ready }
            let stale = games.filter { game in
                guard let snapshot = shown[game.titleID] else { return true }
                return self.now().timeIntervalSince(snapshot.savedAt) > self.maxAge
            }
            let offline = await self.refresh(stale)
            guard !Task.isCancelled else { return }
            self.refreshing = false
            self.phase = self.games.isEmpty && offline ? .offline : .ready
        }
    }

    /// Leaving the store: requests stop; what was found stays on disk.
    public func close() {
        task?.cancel()
        task = nil
        order = []
        found = [:]
        games = []
        refreshing = false
        phase = .idle
    }

    private func publish() {
        let next = order.compactMap { game -> ModCatalogGame? in
            guard let mods = found[game.titleID], !mods.isEmpty else { return nil }
            return ModCatalogGame(titleID: game.titleID, name: game.name, mods: mods)
        }
        if next != games { games = next }
    }

    /// Asks about `games`, `concurrent` at a time; true when any of them found no connection.
    private func refresh(_ games: [ModStoreGame]) async -> Bool {
        var offline = false
        await withTaskGroup(of: (String, Found?, Bool).self) { group in
            var next = 0
            func add() {
                guard next < games.count else { return }
                let game = games[next]
                next += 1
                group.addTask { [weak self] in
                    guard let self else { return (game.titleID, nil, false) }
                    return await self.mods(for: game)
                }
            }
            for _ in 0..<concurrent { add() }
            for await (titleID, result, wasOffline) in group {
                offline = offline || wasOffline
                guard !Task.isCancelled, let game = games.first(where: { $0.titleID == titleID }) else {
                    group.cancelAll()
                    continue
                }
                switch result {
                case .mods(let mods, let gameID):
                    found[titleID] = mods
                    publish()
                    if !self.games.isEmpty { phase = .ready }
                    try? snapshots.save(mods, gameName: game.name, titleID: titleID, gameBananaID: gameID, at: now())
                case .noPage:
                    // No GameBanana page (or not one we are sure of): nothing of the game is shown.
                    found[titleID] = nil
                    publish()
                case nil:
                    break // The answer failed: what was shown stays.
                }
                if Task.isCancelled { group.cancelAll() } else { add() }
            }
        }
        return offline
    }

    private enum Found {
        case mods([AvailableMod], gameID: Int)
        case noPage
    }

    /// The game's mods that work; `.noPage` without a GameBanana page we are sure of; nil when the answer failed.
    private func mods(for game: ModStoreGame) async -> (String, Found?, Bool) {
        do {
            guard let id = try await gameID(for: game) else { return (game.titleID, .noPage, false) }
            var mods: [AvailableMod] = []
            for try await mod in AvailableModsFinder(client: client, titleID: game.titleID).stream(gameID: id) {
                mods.append(mod)
            }
            return (game.titleID, .mods(mods.sorted { $0.rank < $1.rank }, gameID: id), false)
        } catch {
            return (game.titleID, nil, (error as? GameBananaError) == .offline)
        }
    }

    private func gameID(for game: ModStoreGame) async throws -> Int? {
        switch matches.choice(titleID: game.titleID) {
        case .game(let id, _, _): return id
        case .noPage: return nil
        case nil: break
        }
        var results: [GameBananaGame] = []
        for name in game.names.filter({ !$0.isEmpty }).prefix(2) {
            results += try await client.searchGames(name).filter { found in !results.contains { $0.id == found.id } }
        }
        guard !Task.isCancelled,
              case .matched(let match) = GameBananaMatch.decide(names: game.names, results: results.filter { !$0.hasContentRatings })
        else { return nil }
        let page = match.profileURL ?? URL(string: "https://gamebanana.com/games/\(match.id)")!
        try? matches.set(.game(id: match.id, name: match.name, profileURL: page), titleID: game.titleID)
        return match.id
    }
}
