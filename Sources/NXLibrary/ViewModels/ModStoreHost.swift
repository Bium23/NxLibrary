import SwiftUI
import Combine
import os
import NXLibraryCore

/// The Mods card's store: the catalog of your games' mods, the sort, the focus on the page and the mod panel over
/// it. Sections are built once per change of mods or sort, never per frame, and mods found in the background wait
/// while the page moves (`hold(until:)`): the page never rebuilds under a glide.
@MainActor
final class ModStoreHost: ObservableObject {
    let catalog: ModStoreModel
    /// The mod panel and its installs; installs go into the game the mod is for.
    let panel = ModsBandHost()

    @Published var sort: ModStoreSort = .popular {
        didSet { if sort != oldValue { rebuild() } }
    }
    @Published var focus = ModStoreFocus()
    @Published private(set) var sections: [ModStoreSection] = ModStoreLayout.sections(games: [], sort: .popular)
    /// GameBanana records of the installed mods, by title ID then mod id: the Installed and Update chips.
    @Published private(set) var records: [String: [Int: ModRecord]] = [:]
    /// Working mods found and the games they are for, and whether more are being looked for: the card's numbers.
    @Published private(set) var counts: (mods: Int, games: Int, looking: Bool) = (0, 0, false)
    /// Up to four mods' art for the card's cover (`ModStoreLayout.coverArt`), from the snapshots on disk until the
    /// store has looked; the same art either way unless the store finds new mods.
    @Published private(set) var cover: [URL] = []
    /// The cover being decoded before it is shown.
    private var nextCover: [URL] = []
    private var coverTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "local.nxlibrary", category: "gamebanana")
    private var gamesByTitle: [String: PortedGame] = [:]
    private weak var viewModel: AppViewModel?
    private var forwards: Set<AnyCancellable> = []
    private var heldUntil = Date.distantPast
    private var pending: Task<Void, Never>?
    private let snapshots: ModCatalogSnapshots

    init() {
        let services = GameBananaServices.shared
        let caches = AppData.cacheRoot.appendingPathComponent("gamebanana/store")
        snapshots = ModCatalogSnapshots(folder: caches)
        catalog = ModStoreModel(client: services.client, matches: services.matches, snapshots: snapshots)
        // After the catalog has published its new value; held while the page moves.
        catalog.$games.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.update() } }.store(in: &forwards)
        catalog.$refreshing.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.update() } }.store(in: &forwards)
        panel.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &forwards)
    }

    /// The page is moving until `date`: what the catalog finds meanwhile is applied once it rests.
    func hold(until date: Date) {
        if date > heldUntil { heldUntil = date }
    }

    private func update() {
        let wait = heldUntil.timeIntervalSinceNow
        guard wait <= 0 else {
            guard pending == nil else { return }
            pending = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((wait + 0.05) * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                self.pending = nil
                self.update()
            }
            return
        }
        rebuild()
    }

    var focusSections: [ModStoreFocus.Section] { sections.map { .init(kind: $0.kind, count: $0.count) } }

    var isPanelOpen: Bool { panel.isPanelOpen }


    // MARK: - Lifecycle

    /// The card is selected: the store reads its snapshots and refreshes in the background. `games` are your games,
    /// last played first.
    func open(_ games: [PortedGame], viewModel: AppViewModel) {
        self.viewModel = viewModel
        var byTitle: [String: PortedGame] = [:]
        var list: [ModStoreGame] = []
        for game in games {
            guard let titleID = viewModel.modStore(for: game)?.titleID, byTitle[titleID] == nil else { continue }
            byTitle[titleID] = game
            let names = [game.name, viewModel.storeMetadata[game.id]?.name].compactMap { $0 }.filter { !$0.isEmpty }
            list.append(ModStoreGame(titleID: titleID, name: game.name, names: names))
        }
        gamesByTitle = byTitle
        panel.gameBanana.onInstalled = { [weak self] in
            guard let self, let viewModel = self.viewModel else { return }
            self.panel.reloadRecords(viewModel: viewModel)
            self.reloadRecords(all: true)
        }
        catalog.open(list)
    }

    /// The card's cover before the store has looked: the art the store will pick, from the snapshots on disk of
    /// `titleIDs` (your games), read off the main thread. No request.
    func loadCover(titleIDs: Set<String>) {
        guard cover.isEmpty, nextCover.isEmpty else { return }
        let snapshots = self.snapshots
        let matches = GameBananaServices.shared.matches
        let wanted = Set(titleIDs.map { $0.uppercased() })
        Task { [weak self] in
            let urls = await Task.detached(priority: .utility) { () -> [URL] in
                let games = snapshots.loadAll(matches: matches).filter { wanted.contains($0.titleID) }
                    .map { ModCatalogGame(titleID: $0.titleID, name: $0.gameName, mods: $0.mods) }
                return ModStoreLayout.coverArt(games: games)
            }.value
            guard let self, self.cover.isEmpty else { return }
            self.show(cover: urls)
        }
    }

    /// Shows `urls` on the card once all of them are decoded, so the mosaic changes in one crossfade.
    private func show(cover urls: [URL]) {
        guard !urls.isEmpty, urls != nextCover else { return }
        coverTask?.cancel()
        guard urls != cover else { nextCover = []; return }
        nextCover = urls
        coverTask = Task { [weak self] in
            await GameBananaImageView.prepare(urls, maxPixelSize: ModsCardCover.pixelSize)
            guard let self, !Task.isCancelled, self.nextCover == urls else { return }
            self.cover = urls
            self.nextCover = []
        }
    }

    /// Another card or a game is selected: requests and downloads stop, the panel closes.
    func close() {
        guard catalog.phase != .idle || panel.isPanelOpen else { return }
        panel.stop()
        catalog.close()
        pending?.cancel()
        pending = nil
        focus = ModStoreFocus()
        update()
    }

    private func rebuild() {
        let start = Date()
        let next = ModStoreLayout.sections(games: catalog.games, sort: sort)
        if next != sections { sections = next }
        var settled = focus
        settled.settle(in: focusSections)
        if settled != focus { focus = settled }
        let mods = catalog.games.reduce(0) { $0 + $1.mods.count }
        let nextCounts = (mods, catalog.games.count, catalog.refreshing || catalog.phase == .loading)
        if nextCounts != counts { counts = nextCounts }
        show(cover: ModStoreLayout.coverArt(games: catalog.games))
        reloadRecords(all: false)
        prewarm()
        Self.log.notice("store rebuild \(self.sections.count, privacy: .public) sections \(mods, privacy: .public) mods in \(Int(Date().timeIntervalSince(start) * 1000), privacy: .public) ms")
    }

    /// Reads the records of games not read yet (`all`: every game, after an install) off the main thread.
    private func reloadRecords(all: Bool) {
        guard let viewModel else { return }
        let stores = catalog.games.compactMap { game -> (String, ModStore)? in
            guard all || records[game.titleID] == nil, let ported = gamesByTitle[game.titleID],
                  let store = viewModel.modStore(for: ported) else { return nil }
            return (game.titleID, store)
        }
        guard !stores.isEmpty else { return }
        let box = UncheckedBox(stores)
        Task { [weak self] in
            let read = await Task.detached(priority: .utility) { () -> [String: [Int: ModRecord]] in
                Dictionary(box.value.map { ($0.0, $0.1.gameBananaRecords()) }, uniquingKeysWith: { first, _ in first })
            }.value
            guard let self else { return }
            var next = self.records
            next.merge(read) { _, new in new }
            if next != self.records { self.records = next }
        }
    }

    // MARK: - Art

    /// The first tiles of every row, and the Featured art, decoded before the page reaches them.
    private func prewarm() {
        var urls: [URL] = []
        for section in sections {
            urls += section.entries.prefix(section.kind == .featured ? ModStoreLayout.featuredCount : 6)
                .compactMap { $0.mod.images.first ?? $0.mod.thumbnailURL }
        }
        GameBananaImageView.prewarm(urls, maxPixelSize: 700)
        for entry in sections.first(where: { $0.kind == .featured })?.entries ?? [] {
            if let url = entry.mod.images.first ?? entry.mod.thumbnailURL {
                Task { _ = await GameBananaBlur.image(for: url, radius: GameBananaBlur.bannerRadius) }
            }
        }
    }

    // MARK: - Tiles

    func entry(_ kind: ModStoreSectionKind, _ index: Int) -> ModCatalogEntry? {
        guard let section = sections.first(where: { $0.kind == kind }), section.entries.indices.contains(index) else { return nil }
        return section.entries[index]
    }

    /// Installed / Update / the install in progress.
    func chip(for entry: ModCatalogEntry) -> String? {
        switch panel.gameBanana.installs[entry.id] {
        case .downloading(let fraction): return "Downloading \(Int(fraction * 100))%"
        case .installing: return L10n.text("Installing…")
        case .failed: return L10n.text("Didn't install")
        case .done, nil: break
        }
        guard let record = records[entry.titleID]?[entry.id] else { return nil }
        return ModUpdateCheck.update(for: record, in: entry.mod) == nil ? "Installed" : "Update"
    }

    // MARK: - Input

    enum Outcome { case moved, stayed, leave }

    /// Down/Up between sections (Up from the top leaves the store), Left/Right inside one, A activates.
    func handle(_ action: GamepadAction) -> Outcome {
        let sections = focusSections
        var next = focus
        var moved = false
        switch action {
        case .navigateDown: moved = next.down(in: sections)
        case .navigateUp:
            guard next.up(in: sections) else { return .leave }
            moved = true
        case .navigateLeft: moved = next.left(in: sections)
        case .navigateRight: moved = next.right(in: sections)
        case .confirm:
            activate(focus.kind, focus.index)
            return .stayed
        case .cancel:
            return .leave
        default:
            return .stayed
        }
        if moved { focus = next }
        return moved ? .moved : .stayed
    }

    func pointerFocus(_ kind: ModStoreSectionKind, _ index: Int) {
        var next = focus
        next.focus(kind, index: index, in: focusSections)
        if next != focus { focus = next }
    }

    func activate(_ kind: ModStoreSectionKind, _ index: Int) {
        pointerFocus(kind, index)
        if kind == .sort {
            guard ModStoreSort.allCases.indices.contains(index) else { return }
            SoundEffectService.shared.play(.click)
            sort = ModStoreSort.allCases[index]
            return
        }
        guard let viewModel, let entry = entry(kind, index), let game = gamesByTitle[entry.titleID] else { return }
        panel.openStoreDetail(entry.mod, game: game, viewModel: viewModel)
    }

    func game(for titleID: String) -> PortedGame? { gamesByTitle[titleID] }
}

/// Values handed to a background read once and never touched again on the main thread.
private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
