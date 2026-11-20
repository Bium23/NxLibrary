import AppKit
import Foundation
import NXLibraryCore
import ArcanePorting

/// What the Nintendo store says about each Switch game (name, description, screenshots, store page), in the app
/// language: loaded when a game is selected or opened, kept on disk, brought to a new language in the background one
/// request at a time, with LaunchBox screenshots when the store has none and the player's Change metadata choices
/// laid over it. The screens that show it observe it on their own: Spotlight, Collection, the game page, Game options,
/// Change artwork, Change metadata, the launch screen and the session card. It reaches the rest of Arcane only
/// through `app`: the library, the focused game and the personalization key.
final class StoreMetadataModel: ObservableObject {
    /// The coordinator: library, focused game and personalization keys.
    unowned let app: AppViewModel

    init(app: AppViewModel) {
        self.app = app
    }

    @Published var storeMetadata: [UUID: NintendoStoreMetadata] = [:]
    @Published var storeMetadataLoading: Set<UUID> = []
    @Published var storeMetadataErrors: [UUID: String] = [:]
    private lazy var storeMetadataService = NintendoStoreMetadataService()
    private var metadataLocaleGeneration = UUID()
    private var localizedMetadataRefresh: Task<Void, Never>?

    func loadStoreMetadata(for game: PortedGame) {
        Task { @MainActor [weak self] in await self?.fetchStoreMetadata(for: game) }
    }

    /// Returns once `game` has metadata in the app language, or the request failed; a request already running for
    /// it is not repeated. A language change while it runs discards the answer. True when the app language's
    /// description is settled (`languageResolved`), false after an outage.
    @discardableResult
    @MainActor private func fetchStoreMetadata(for game: PortedGame) async -> Bool {
        let locale = L10n.context
        let generation = metadataLocaleGeneration
        guard let titleId = game.titleId, !titleId.isEmpty else { return true }
        if storeMetadataLoading.contains(game.id) { return true }
        if let existing = storeMetadata[game.id], storeMetadataService.isFresh(existing, locale: locale) {
            loadFallbackScreenshots(for: game)
            return storeMetadataService.languageResolved(existing, locale: locale)
        }

        storeMetadataLoading.insert(game.id)
        storeMetadataErrors[game.id] = nil
        var resolved = false
        do {
            let metadata = try await storeMetadataService.metadata(for: game, locale: locale)
            guard metadataLocaleGeneration == generation else { return true }
            setStoreMetadata(metadata, for: game)
            resolved = storeMetadataService.languageResolved(metadata, locale: locale)
        } catch {
            guard metadataLocaleGeneration == generation else { return true }
            storeMetadataErrors[game.id] = error.localizedDescription
        }
        storeMetadataLoading.remove(game.id)
        loadFallbackScreenshots(for: game)
        return resolved
    }

    /// A language change only resets presentation metadata, never the library, personal picks or game settings.
    func refreshLocalizedMetadata() {
        metadataLocaleGeneration = UUID()
        let generation = metadataLocaleGeneration
        localizedMetadataRefresh?.cancel()
        storeMetadataErrors.removeAll()
        storeMetadataLoading.removeAll()
        let games = app.libraryGames
        let locale = L10n.context
        let service = storeMetadataService
        // Keep a visible description while another language loads. Disk reads do not block the UI.
        localizedMetadataRefresh = Task { @MainActor [weak self] in
            let entries = await Task.detached(priority: .userInitiated) {
                games.compactMap { game -> (PortedGame, NintendoStoreMetadata)? in
                    guard let titleID = game.titleId,
                          let cached = service.cachedForDisplay(for: titleID, locale: locale) else { return nil }
                    return (game, cached)
                }
            }.value
            guard let self, !Task.isCancelled, self.metadataLocaleGeneration == generation else { return }
            for (game, metadata) in entries { self.setStoreMetadata(metadata, for: game) }
            // Every game gets the new language without being opened, the focused one first.
            let focused = self.app.currentFocusedGame
            self.languageFetchQueue = []
            self.languageFetchWaiting = []
            self.languageFetchRounds = 0
            self.languageFetchResume?.cancel()
            self.queueLanguageFetch((focused.map { [$0] } ?? []) + games.filter { $0.id != focused?.id })
        }
    }

    /// Games still to bring to the app language in the background, asked one request at a time.
    private var languageFetchQueue: [PortedGame] = []
    /// Games whose request met an outage; asked again when the connection returns or after `languageFetchPause`.
    private var languageFetchWaiting: [PortedGame] = []
    private var languageFetchTask: Task<Void, Never>?
    private var languageFetchResume: Task<Void, Never>?
    /// Timed retries since the last language change or reconnection: a game that always fails is not asked forever.
    private var languageFetchRounds = 0
    static let languageFetchRoundLimit = 3
    /// Three outages in a row mean the provider or the network is down: the pass stops instead of asking every game.
    static let languageFetchFailureLimit = 3
    static let languageFetchPause: UInt64 = 300_000_000_000
    private lazy var connectivity = ConnectivityWatcher { [weak self] in self?.connectionReturned() }

    /// Adds `games` to the background queue; one loop drains it and always asks in the current app language.
    private func queueLanguageFetch(_ games: [PortedGame]) {
        for game in games where !languageFetchQueue.contains(where: { $0.id == game.id }) { languageFetchQueue.append(game) }
        guard languageFetchTask == nil, !languageFetchQueue.isEmpty else { return }
        connectivity.start()
        languageFetchTask = Task { @MainActor [weak self] in
            var outages = 0
            while let self, !self.languageFetchQueue.isEmpty {
                let game = self.languageFetchQueue.removeFirst()
                if await self.fetchStoreMetadata(for: game) { outages = 0; continue }
                if !self.languageFetchWaiting.contains(where: { $0.id == game.id }) { self.languageFetchWaiting.append(game) }
                outages += 1
                if outages >= Self.languageFetchFailureLimit {
                    self.languageFetchWaiting += self.languageFetchQueue
                    self.languageFetchQueue = []
                }
            }
            guard let self else { return }
            self.languageFetchTask = nil
            if !self.languageFetchWaiting.isEmpty, self.languageFetchRounds < Self.languageFetchRoundLimit {
                self.languageFetchRounds += 1
                self.scheduleLanguageResume()
            }
        }
    }

    /// Asks the waiting games again after a pause, for a provider that was busy while the network stayed up.
    private func scheduleLanguageResume() {
        languageFetchResume?.cancel()
        languageFetchResume = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: Self.languageFetchPause) } catch { return }
            self?.resumeLanguageFetch()
        }
    }

    private func connectionReturned() {
        guard !languageFetchWaiting.isEmpty else { return }
        storeMetadataService.forgetDescriptionRetries()
        languageFetchRounds = 0
        resumeLanguageFetch()
    }

    private func resumeLanguageFetch() {
        languageFetchResume?.cancel()
        languageFetchResume = nil
        let waiting = languageFetchWaiting
        languageFetchWaiting = []
        queueLanguageFetch(waiting)
    }

    /// Fills metadata from the disk cache without starting a network request, in
    /// another language when the app's is not cached yet (`cachedForDisplay`).
    /// The library uses this so a previously viewed game paints its title,
    /// description and hero immediately when selected.
    /// A game shown in another language (the language changed while the app was closed) is
    /// queued for the app's language in the background.
    func preloadCachedStoreMetadata() {
        let locale = L10n.context
        var otherLanguage: [PortedGame] = []
        for game in app.libraryGames {
            guard storeMetadata[game.id] == nil,
                  let titleId = game.titleId,
                  !titleId.isEmpty,
                  let metadata = storeMetadataService.cachedForDisplay(for: titleId, locale: locale) else { continue }
            setStoreMetadata(metadata, for: game)
            if !storeMetadataService.isInLanguage(metadata, locale: locale) { otherLanguage.append(game) }
        }
        queueLanguageFetch(otherLanguage)
    }

    /// The store's metadata as fetched, before the player's choices are laid over it.
    private var storeMetadataOriginals: [UUID: NintendoStoreMetadata] = [:]

    /// Keeps the fetched metadata and shows it with the player's choices (`MetadataPicks`) over it.
    private func setStoreMetadata(_ metadata: NintendoStoreMetadata, for game: PortedGame) {
        storeMetadataOriginals[game.id] = metadata
        let shown = MetadataPicks.shared.applied(to: metadata, titleID: app.personalizationKey(for: game))
        storeMetadata[game.id] = screenshotFallback.filled(shown)
    }

    private let screenshotFallback = ScreenshotFallbackStore()
    /// Games whose LaunchBox screenshots are being looked up; Details waits before saying it has none.
    @Published private(set) var screenshotLookups: Set<UUID> = []

    /// A game whose metadata has no screenshots (Title DB has none for Switch 2 games) asks LaunchBox once, when the
    /// game is selected or opened as its metadata is, and keeps the answer for 30 days. A scan never asks.
    func loadFallbackScreenshots(for game: PortedGame) {
        guard let titleId = game.titleId, !titleId.isEmpty, let metadata = storeMetadata[game.id],
              !storeMetadataLoading.contains(game.id), screenshotFallback.wantsLookup(metadata),
              screenshotLookups.insert(game.id).inserted else { return }
        let names = [game.name, metadata.name].reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let store = screenshotFallback
        Task { @MainActor [weak self] in
            let urls = await LaunchBoxArt.screenshots(names: names, switch2: game.isSwitch2)
            guard let self else { return }
            self.screenshotLookups.remove(game.id)
            // Unreachable: asked again next time Details opens.
            guard let urls else { return }
            try? store.save(.init(urls: urls, fetchedAt: Date()), for: titleId)
            if let original = self.storeMetadataOriginals[game.id] { self.setStoreMetadata(original, for: game) }
        }
    }

    /// The metadata as the store gave it: what Automatic means in Change metadata.
    func storeMetadataAsFetched(for game: PortedGame) -> NintendoStoreMetadata? {
        storeMetadataOriginals[game.id]
    }

    /// Keeps the player's value for a field, or (nil) goes back to the store's.
    func pickMetadata(_ value: String?, field: MetadataField, for game: PortedGame) {
        let key = app.personalizationKey(for: game)
        if let value { MetadataPicks.shared.set(value, titleID: key, field: field) }
        else { MetadataPicks.shared.remove(titleID: key, field: field) }
        if let original = storeMetadataOriginals[game.id] { setStoreMetadata(original, for: game) }
    }

    func metadataCacheSize() -> Int64 {
        storeMetadataService.cacheSize() + WikipediaDescriptionService.shared.cacheSize()
    }

    func clearMetadataCache() {
        storeMetadataService.clearCache()
        WikipediaDescriptionService.shared.clearCache()
        storeMetadata.removeAll()
        storeMetadataOriginals.removeAll()
    }

    func nintendoStoreSearchURL(for game: PortedGame) -> URL? {
        var components = URLComponents(string: "https://www.nintendo.com/us/search/")
        components?.fragment = "q=\(game.name)&p=1&cat=gme&sort=df"
        return components?.url
    }
}
