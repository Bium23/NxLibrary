import Foundation
import NXLibraryCore

/// The achievements of the Steam games shown, for the page's card and the Achievements screen.
/// Steam's cache is read off the main thread (`SteamAchievementReader.read`) when a game is selected,
/// when the Achievements screen opens and after a Steam session ends; Steam's public rarity follows
/// (`SteamMetadataService.achievementPercents`). Nothing is written to Steam's files, logged or kept
/// beyond the summaries in memory; the rarity and icons are cached by `SteamMetadataService`.
@MainActor
final class SteamAchievementsStore: ObservableObject {
    static let shared = SteamAchievementsStore()

    /// By AppID. Missing: not read yet, no achievements, or nothing for the signed-in account.
    @Published private(set) var summaries: [UInt32: AchievementSummary] = [:]

    private var root: URL?
    private var language: String?
    /// Bumped whenever the folder or the language changes, so a read started before is dropped.
    private var generation = 0
    private var reading: Set<UInt32> = []
    private var readAgain: Set<UInt32> = []
    /// The game read last (the one on screen): the folder changing and a session ending read it again.
    private var current: UInt32?
    /// Games with a summary, oldest first; only the last `kept` stay, so going back to one shows it at once.
    private var order: [UInt32] = []
    private static let kept = 16
    /// The last reading of each game, rebuilt into a summary when the rarity arrives.
    private var latest: [UInt32: [SteamAchievement]] = [:]
    /// The rarity last fetched for each game kept (`SteamMetadataService` keeps it on disk too).
    private var percents: [UInt32: [String: Double]] = [:]
    private var followUp: Task<Void, Never>?

    /// The Steam source's folder while it is enabled.
    func setSources(_ sources: [CatalogSourceConfiguration]) {
        let folder = sources.first { $0.integration == .steam && $0.isEnabled }?.rootURL
        guard folder != root else { return }
        root = folder
        reset()
        // Same game, another folder: read again what was shown.
        reloadCurrent()
    }

    /// Reads one game's achievements; one read per AppID at a time, a request meanwhile reads again after it.
    func load(appID: UInt32, language: String) {
        if language != self.language {
            self.language = language
            reset()
        }
        current = appID
        guard let root else {
            summaries = [:]
            return
        }
        guard !reading.contains(appID) else {
            readAgain.insert(appID)
            return
        }
        reading.insert(appID)
        let ticket = generation
        Task.detached(priority: .utility) {
            let achievements = (try? SteamAchievementReader.read(root: root, appID: appID, language: language)) ?? nil
            await MainActor.run { [weak self] in self?.finish(appID, achievements, ticket: ticket) }
        }
    }

    /// Steam writes the unlock times as the game quits or a little later: read now and once more in a minute.
    /// Only the game on screen: another one is read again when it is selected.
    func sessionEnded() {
        reloadCurrent()
        followUp?.cancel()
        followUp = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            self?.reloadCurrent()
        }
    }

    func stop() {
        followUp?.cancel(); followUp = nil
        reset()
        current = nil
    }

    private func reloadCurrent() {
        guard let language, let current else { return }
        load(appID: current, language: language)
    }

    private func reset() {
        generation += 1
        reading = []
        readAgain = []
        latest = [:]
        percents = [:]
        order = []
        summaries = [:]
    }

    private func finish(_ appID: UInt32, _ achievements: [SteamAchievement]?, ticket: Int) {
        guard ticket == generation else { return }
        reading.remove(appID)
        defer {
            if readAgain.remove(appID) != nil, let language { load(appID: appID, language: language) }
        }
        guard let achievements, !achievements.isEmpty else {
            forget(appID)
            return
        }
        // The counts first, with the rarity known so far; Steam's (or its cache's) answer follows.
        keep(appID)
        latest[appID] = achievements
        summaries[appID] = AchievementSummary(achievements: achievements, percents: percents[appID] ?? [:])
        Task { [weak self] in
            guard let fetched = await SteamMetadataService.shared.achievementPercents(appID: appID) else { return }
            self?.apply(fetched, appID: appID, ticket: ticket)
        }
    }

    private func keep(_ appID: UInt32) {
        order.removeAll { $0 == appID }
        order.append(appID)
        while order.count > Self.kept { forget(order[0]) }
    }

    private func forget(_ appID: UInt32) {
        order.removeAll { $0 == appID }
        latest[appID] = nil
        percents[appID] = nil
        summaries[appID] = nil
    }

    private func apply(_ fetched: [String: Double], appID: UInt32, ticket: Int) {
        // The newest reading, which may have finished while Steam answered; a game forgotten since stays forgotten.
        guard ticket == generation, let achievements = latest[appID] else { return }
        percents[appID] = fetched
        let summary = AchievementSummary(achievements: achievements, percents: fetched)
        if summaries[appID] != summary { summaries[appID] = summary }
    }
}
