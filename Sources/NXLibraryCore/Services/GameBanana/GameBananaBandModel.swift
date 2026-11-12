import Foundation
import Combine
import os

/// The GameBanana part of one game's Mods band: which GameBanana game it is, the mods that work, and their installs.
/// Requests run only between `start` (the page appears) and `stop` (it goes away).
@MainActor
public final class GameBananaBandModel: ObservableObject {
    public enum Phase: Equatable {
        case idle, matching
        case ask([GameBananaGame])
        case noPage, looking, ready
        case noneWork(URL)
        case offline, failed
    }

    public enum InstallState: Equatable {
        case downloading(Double)
        case installing
        case failed(String)
        /// Installed; the sentence to show, if any (the overlay line was full).
        case done(String?)
    }

    @Published public private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { Self.log.notice("phase \(String(describing: self.phase), privacy: .public) available \(self.available.count, privacy: .public)") } }
    }
    private static let log = Logger(subsystem: "local.nxlibrary", category: "gamebanana")
    @Published public private(set) var available: [AvailableMod] = []
    @Published public private(set) var installs: [Int: InstallState] = [:]
    /// The file each mod's install is for, while it runs and once it has ended.
    @Published public private(set) var installFiles: [Int: Int] = [:]
    @Published public private(set) var match: GameBananaChoice?

    /// Runs after an install changed the mods folder (the page re-reads its mods).
    public var onInstalled: (() -> Void)?
    /// Decodes the art of mods about to show (the app's image cache), so a group of tiles shows whole.
    public var prepareImages: (@MainActor ([URL]) async -> Void)?
    /// How long a group of mods waits for its art, in seconds; slower art fades in once the mods show.
    public var imageWait: Double = 1.2

    private let client: GameBananaClient
    private let matches: GameBananaMatchStore
    private let userAgent: String
    private var names: [String] = []
    private var store: ModStore?
    private var task: Task<Void, Never>?
    private var downloads: [Int: ModDownload] = [:]
    private var cancelled: Set<Int> = []
    /// The download attempt in progress for each mod.
    private var attempts: [Int: UUID] = [:]
    private var startedFor: String?
    /// Games whose leftovers of an interrupted install were cleared in this run.
    private static var swept: Set<String> = []

    public init(client: GameBananaClient, matches: GameBananaMatchStore, userAgent: String) {
        self.client = client
        self.matches = matches
        self.userAgent = userAgent
    }

    // MARK: - Lifecycle

    public func start(names: [String], store: ModStore?) {
        guard let store else {
            Self.log.notice("start without a title ID")
            return stop()
        }
        Self.log.notice("start \(store.titleID, privacy: .public)")
        self.names = names.filter { !$0.isEmpty }
        self.store = store
        if startedFor == store.titleID, phase != .idle { return }
        if startedFor != store.titleID { stop() }
        // Nothing of this run is installing yet, so a staging folder or download left now is from a run that quit
        // mid-install.
        if store.isWritable, Self.swept.insert(store.titleID).inserted { store.removeLeftoverInstalls() }
        self.store = store
        startedFor = store.titleID
        resolve()
    }

    /// The store's mod panel: installs go into this game's folder, without asking GameBanana which game it is.
    /// A download already running keeps the folder it started with.
    public func attach(store: ModStore) {
        if store.isWritable, Self.swept.insert(store.titleID).inserted { store.removeLeftoverInstalls() }
        self.store = store
    }

    public func stop() {
        task?.cancel()
        task = nil
        downloads.values.forEach { $0.cancel() }
        downloads = [:]
        attempts = [:]
        cancelled = []
        startedFor = nil
        available = []
        installs = [:]
        installFiles = [:]
        match = nil
        phase = .idle
    }

    public func retry() {
        if case .game = match { look() } else { resolve() }
    }

    // MARK: - Matching

    private func resolve() {
        guard let store else { return }
        available = []
        match = matches.choice(titleID: store.titleID)
        switch match {
        case .game: look()
        case .noPage: phase = .noPage
        case nil: matchByName()
        }
    }

    private func matchByName() {
        task?.cancel()
        phase = .matching
        let names = self.names
        let client = self.client
        task = Task { [weak self] in
            do {
                var results: [GameBananaGame] = []
                for name in names.prefix(2) {
                    results += try await client.searchGames(name).filter { found in !results.contains { $0.id == found.id } }
                }
                guard !Task.isCancelled, let self else { return }
                switch GameBananaMatch.decide(names: names, results: results.filter { !$0.hasContentRatings }) {
                case .matched(let game): self.confirm(game)
                case .ask(let candidates): self.phase = .ask(candidates)
                case .none: self.phase = .noPage
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = (error as? GameBananaError) == .offline ? .offline : .failed
            }
        }
    }

    /// The player's (or the automatic) choice of GameBanana game.
    public func confirm(_ game: GameBananaGame) {
        guard let store else { return }
        let page = game.profileURL ?? URL(string: "https://gamebanana.com/games/\(game.id)")!
        let choice = GameBananaChoice.game(id: game.id, name: game.name, profileURL: page)
        try? matches.set(choice, titleID: store.titleID)
        match = choice
        look()
    }

    public func noneOfThese() {
        guard let store else { return }
        task?.cancel()
        try? matches.set(.noPage, titleID: store.titleID)
        match = .noPage
        available = []
        phase = .noPage
    }

    public func search(_ text: String) async -> [GameBananaGame] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return ((try? await self.client.searchGames(query)) ?? []).filter { !$0.hasContentRatings }
    }

    public var matchedName: String? {
        if case .game(_, let name, _) = match { return name }
        return nil
    }

    public var matchedPage: URL? {
        if case .game(_, _, let url) = match { return url }
        return nil
    }

    // MARK: - Mods

    private func look() {
        guard let store, case .game(let id, _, let page) = match else { return }
        task?.cancel()
        available = []
        phase = .looking
        let finder = AvailableModsFinder(client: self.client, titleID: store.titleID,
                                         installed: store.gameBananaRecords().keys.sorted())
        task = Task { [weak self] in
            // The mods show in two groups at most, each with its art: a row's worth beside Add mods as soon as
            // there is one, the rest once the search has ended. One at a time, each tile came in on its own and
            // filled in later, and the band shifted under the player's eyes.
            var waiting: [AvailableMod] = []
            do {
                for try await mod in finder.stream(gameID: id) {
                    guard let self, !Task.isCancelled else { return }
                    waiting.append(mod)
                    if self.available.isEmpty, waiting.count >= Self.firstGroup {
                        guard await self.show(waiting) else { return }
                        waiting = []
                    }
                }
                guard let self, await self.show(waiting) else { return }
                self.phase = self.available.isEmpty ? .noneWork(page) : .ready
            } catch {
                guard let self, await self.show(waiting) else { return }
                if self.available.isEmpty {
                    self.phase = (error as? GameBananaError) == .offline ? .offline : .failed
                } else {
                    self.phase = .ready
                }
            }
        }
    }

    /// The first group: the first row beside Add mods.
    static let firstGroup = 5

    /// Shows `group` once its art is decoded (or `imageWait` has passed); false when the search was replaced
    /// meanwhile, so another game's mods never show.
    private func show(_ group: [AvailableMod]) async -> Bool {
        guard !Task.isCancelled else { return false }
        guard !group.isEmpty else { return true }
        await readyArt(of: group)
        guard !Task.isCancelled else { return false }
        available += group.sorted { $0.rank < $1.rank }
        return true
    }

    private func readyArt(of group: [AvailableMod]) async {
        guard let prepare = prepareImages else { return }
        let urls = group.compactMap(\.thumbnailURL)
        guard !urls.isEmpty else { return }
        let wait = UInt64(max(imageWait, 0) * 1_000_000_000)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce(done)
            Task { @MainActor in
                await prepare(urls)
                once.resume()
            }
            Task {
                try? await Task.sleep(nanoseconds: wait)
                once.resume()
            }
        }
    }

    /// The band's status line, under its title.
    public var statusLine: String? {
        switch phase {
        case .looking: return L10n.text("Looking for mods that work…")
        case .ask: return L10n.text("Is this the right game?")
        case .noPage: return L10n.text("No GameBanana page found")
        case .noneWork: return L10n.text("No mods for this game work with NX Library yet")
        case .offline: return L10n.text("No connection. Mods you installed still work.")
        case .failed: return L10n.text("GameBanana didn't answer. Try again in a moment.")
        case .idle, .matching, .ready: return nil
        }
    }

    /// The status tiles after the mods.
    public var statusTiles: [ModsBandAction] {
        switch phase {
        case .ask(let candidates): return candidates.map { .candidate($0.id) } + [.noneOfThese]
        case .noPage: return [.findGame]
        case .noneWork(let page): return [.openPage(page), .wrongGame]
        case .offline, .failed: return [.retry]
        case .ready, .looking: return matchedName == nil ? [] : [.wrongGame]
        case .idle, .matching: return []
        }
    }

    public func candidate(_ id: Int) -> GameBananaGame? {
        if case .ask(let candidates) = phase { return candidates.first { $0.id == id } }
        return nil
    }

    // MARK: - Installing

    /// The install `fileID`'s row shows: the mod's install when it is for that file.
    public func installState(mod modID: Int, file fileID: Int) -> InstallState? {
        installFiles[modID] == fileID ? installs[modID] : nil
    }

    /// Whether one of the mod's files is downloading or installing: the mod takes one install at a time.
    public func isInstalling(_ modID: Int) -> Bool {
        switch installs[modID] {
        case .downloading, .installing: return true
        default: return false
        }
    }

    public func install(_ mod: AvailableMod, file: GameBananaFile) {
        guard let store, downloads[mod.id] == nil, installs[mod.id] != .installing else { return }
        installFiles[mod.id] = file.id
        guard store.isWritable else {
            installs[mod.id] = .failed(ModInstallError.notAllowed.message)
            return
        }
        cancelled.remove(mod.id)
        installs[mod.id] = .downloading(0)
        let archive = store.modsFolder.appendingPathComponent(".installing-\(UUID().uuidString).download")
        // Each attempt answers only for itself: a stopped download that finishes late never touches a new one.
        let attempt = UUID()
        let download = ModDownload(
            file: file, destination: archive, userAgent: userAgent,
            progress: { [weak self] fraction in
                Task { @MainActor in
                    guard let self, self.attempts[mod.id] == attempt, case .downloading = self.installs[mod.id] else { return }
                    self.installs[mod.id] = .downloading(min(max(fraction, 0), 1))
                }
            },
            complete: { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.attempts[mod.id] == attempt else {
                        if case .success(let archive) = result { try? FileManager.default.removeItem(at: archive) }
                        return
                    }
                    self.attempts[mod.id] = nil
                    self.downloaded(result, mod: mod, file: file, store: store)
                }
            })
        attempts[mod.id] = attempt
        downloads[mod.id] = download
        download.start()
    }

    public func cancel(_ modID: Int) {
        guard let download = downloads[modID] else { return }
        cancelled.insert(modID)
        download.cancel()
    }

    private func downloaded(_ result: Result<URL, ModInstallError>, mod: AvailableMod, file: GameBananaFile, store: ModStore) {
        downloads[mod.id] = nil
        if cancelled.remove(mod.id) != nil {
            if case .success(let archive) = result { try? FileManager.default.removeItem(at: archive) }
            installs[mod.id] = nil
            installFiles[mod.id] = nil
            return
        }
        switch result {
        case .failure(let error):
            installs[mod.id] = .failed(error.message)
        case .success(let archive):
            installs[mod.id] = .installing
            Task { [weak self] in
                let outcome = await Task.detached(priority: .userInitiated) { () -> Result<ModInstallResult, ModInstallError> in
                    defer { try? FileManager.default.removeItem(at: archive) }
                    do { return .success(try ModInstaller(store: store).install(archive: archive, file: file, mod: mod)) }
                    catch { return .failure(error as? ModInstallError ?? .writeFailed(error.localizedDescription)) }
                }.value
                guard let self else { return }
                switch outcome {
                case .success(let result): self.installs[mod.id] = .done(result.message)
                case .failure(let error): self.installs[mod.id] = .failed(error.message)
                }
                self.onInstalled?()
            }
        }
    }
}

/// Resumes a continuation the first time it is asked to: the art, or the end of the wait, whichever comes first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }

    func resume() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }
}
