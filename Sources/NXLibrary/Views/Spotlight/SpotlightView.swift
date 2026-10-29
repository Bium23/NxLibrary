import SwiftUI
import AppKit
import NXLibraryCore

/// Spotlight, the home screen (spec §5.2, Selene Main.xaml HOME): one row of
/// square tiles under the filter tabs, the selected game's logo, pills and
/// stats, its screenshots, over its art. All lengths are Selene units on the
/// centred 1920 × 1080 stage; the backdrop and the row reach the window edges.
public struct SpotlightView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var playSessions: PlaySessionStore
    @ObservedObject var artwork: ArtworkStore

    @Environment(\.seleneCanvas) var canvas
    @Environment(\.seleneReduceMotion) var reduceMotion

    @State var heroImage: NSImage?
    @State var heroKey = "none"
    /// Bumped when a logo lands in `GameArtLoader`'s cache, to redraw.
    @State var logoTick = 0
    @State var keyMonitor: Any?
    @State var hadGames = false

    public init(viewModel: AppViewModel, router: AppRouter, settings: AppSettingsStore,
                playSessions: PlaySessionStore, artwork: ArtworkStore) {
        self.viewModel = viewModel
        self.router = router
        self.settings = settings
        self.playSessions = playSessions
        self.artwork = artwork
    }

    // MARK: - Model

    var filter: LibraryFilter { viewModel.librarySelection.query.filter }

    /// The filtered, visible games, most recently played first.
    var games: [PortedGame] {
        LibraryQuery(filter: filter).apply(to: viewModel.libraryGames, history: playSessions)
    }

    var items: [SpotlightItem] {
        SpotlightRow.build(games: games,
                           enabledCards: settings.settings.spotlightCards,
                           order: settings.settings.spotlightOrder)
    }

    var selectedItem: SpotlightItem? { viewModel.spotlight.selectedItem(in: items) }

    var selectedGame: PortedGame? {
        guard case .game(let id) = selectedItem else { return nil }
        return viewModel.libraryGames.first { $0.id == id }
    }

    var screenshotCount: Int {
        guard let game = selectedGame else { return 0 }
        let urls = viewModel.storeMetadata[game.id]?.screenshotURLs ?? []
        return min(urls.count, SpotlightScreenshotStrip.maxCount)
    }

    // MARK: - Body

    public var body: some View {
        let items = self.items
        let gamesByID = Dictionary(viewModel.libraryGames.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let state = viewModel.spotlight
        ZStack(alignment: .topLeading) {
            SeleneArtBackground(image: heroImage, imageKey: heroKey,
                                shade: settings.settings.backgroundShade)
            stage(items: items, gamesByID: gamesByID, state: state)
                .frame(width: canvas.stageSize.width, height: canvas.stageSize.height, alignment: .topLeading)
                .offset(x: canvas.stageOrigin.x, y: canvas.stageOrigin.y)
        }
        .frame(width: canvas.size.width, height: canvas.size.height, alignment: .topLeading)
        .clipped()
        .onAppear(perform: appear)
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: viewModel.libraryGames) { _ in gamesChanged() }
        .onChange(of: filter) { _ in reconcile() }
        .onChange(of: settings.settings.spotlightCards) { _ in reconcile() }
        .onChange(of: settings.settings.spotlightOrder) { _ in reconcile() }
        .onChange(of: viewModel.spotlight.selectedKey) { _ in selectionChanged() }
        .onReceive(NotificationCenter.default.publisher(for: .nxSpotlightGamepadAction)) { note in
            if let action = note.object as? GamepadAction { handle(action) }
        }
        .task(id: heroTaskKey) { await loadHero() }
        .task(id: logoTaskKey) { await loadLogo() }
    }

    private func stage(items: [SpotlightItem], gamesByID: [UUID: PortedGame],
                       state: SpotlightState) -> some View {
        ZStack(alignment: .topLeading) {
            SpotlightTopBar(filter: filter, showClock: settings.settings.showClock,
                            onSelect: { setFilter($0) })

            SpotlightRowView(
                items: items,
                gamesByID: gamesByID,
                selectedKey: state.selectedKey,
                isEmptyFilter: items.contains { if case .game = $0 { return true } else { return false } }
                    ? nil : filter,
                steamGridDbApiKey: settings.settings.steamGridDbApiKey,
                artwork: artwork,
                steamGridDB: viewModel.steamGridDB,
                coverURL: { viewModel.storeMetadata[$0.id]?.imageURL },
                onSelect: { item in
                    mutate { $0.select(item) }
                },
                onActivate: { item in
                    mutate { $0.select(item) }
                    activate(item)
                }
            )
            .offset(y: canvas.u(130))

            info(state: state)
                .offset(x: canvas.u(80), y: canvas.u(420))

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                SeleneHintsBar(left: globalHints, right: contextHints(state), bottom: 40, leftInset: 18)
            }
        }
    }

    @ViewBuilder
    private func info(state: SpotlightState) -> some View {
        if let game = selectedGame {
            let metadata = viewModel.storeMetadata[game.id]
            VStack(alignment: .leading, spacing: 0) {
                SpotlightGameInfoView(
                    game: game,
                    logo: logo(for: game),
                    presentation: LibraryPresentation(
                        game: game, metadata: metadata,
                        totalPlaytime: playSessions.totalDuration(for: game.id),
                        lastPlayed: playSessions.lastPlayed(for: game.id)),
                    isRunning: playSessions.isRunning(gameID: game.id),
                    focusedPill: state.focus == .pills ? state.pillIndex : nil,
                    onPill: { index in
                        mutate { $0.focus = .pills; $0.pillIndex = index }
                        pressPill(index, game: game)
                    },
                    onHoverPill: { index in
                        mutate { $0.focus = .pills; $0.pillIndex = index }
                    }
                )
                .id(game.id)

                SpotlightScreenshotStrip(
                    titleID: game.titleId ?? game.uniqueKey,
                    urls: metadata?.screenshotURLs ?? [],
                    known: metadata != nil || !viewModel.storeMetadataLoading.contains(game.id),
                    focusedIndex: state.focus == .strip ? state.stripIndex : nil,
                    artwork: artwork,
                    onSelect: { index in mutate { $0.focus = .strip; $0.stripIndex = index } }
                )
                .padding(.top, canvas.u(34))
            }
        } else if case .card(let card) = selectedItem {
            // Selene's card panels sit 40 under the row, 10 lower than a game's.
            SpotlightCardInfoView(card: card)
                .padding(.top, canvas.u(10))
        }
    }

    private func logo(for game: PortedGame) -> NSImage? {
        _ = logoTick
        return GameArtLoader.shared.cachedLogo(for: game)
    }

    // MARK: - Hints

    private var globalHints: [HintItem] {
        [HintItem(nil, "Collection", glyph: .spotlight, hold: "Hold: Search"),
         HintItem(nil, "Menu", glyph: .menu, hold: "Hold: Settings")]
    }

    private func contextHints(_ state: SpotlightState) -> [HintItem] {
        switch state.focus {
        case .pills:
            return [HintItem(.a, "Select")]
        case .strip:
            return []
        case .row:
            switch selectedItem {
            case .card(let card):
                return card == .activity ? [] : [HintItem(.a, "Open")]
            case .game:
                guard let game = selectedGame else { return [] }
                if game.isPlayableLocally {
                    return [HintItem(.x, "Details"), HintItem(.y, "Game options"), HintItem(.a, "Play")]
                }
                return [HintItem(.y, "Game options"), HintItem(.a, "Details")]
            case nil:
                return []
            }
        }
    }

    // MARK: - Selection

    func mutate(_ change: (inout SpotlightState) -> Void) {
        var state = viewModel.spotlight
        change(&state)
        if state != viewModel.spotlight { viewModel.spotlight = state }
    }

    private func appear() {
        installKeyMonitor()
        viewModel.preloadCachedStoreMetadata()
        if !viewModel.spotlight.startingTabApplied {
            mutate { $0.startingTabApplied = true }
            viewModel.librarySelection.query.filter = LibraryFilter(startingTab: settings.settings.startingTab)
        }
        hadGames = !games.isEmpty
        reconcile()
        selectionChanged()
    }

    private func gamesChanged() {
        viewModel.preloadCachedStoreMetadata()
        let hasGames = !games.isEmpty
        // The library loads after the first frame: a card picked while it was
        // empty gives way to the restored (or first) game.
        if !hadGames, hasGames, case .card = selectedItem {
            mutate { $0.selectedKey = nil }
        }
        hadGames = hasGames
        reconcile()
    }

    func reconcile() {
        let preferred = settings.settings.restoreLastGame ? settings.settings.lastSelectedGameID : nil
        let items = self.items
        mutate { $0.reconcile(with: items, preferredGameID: preferred) }
    }

    func setFilter(_ next: LibraryFilter) {
        guard next != filter else { return }
        viewModel.librarySelection.query.filter = next
        mutate { $0.focus = .row }
        SoundEffectService.shared.play(.tabSwitch)
    }

    private func selectionChanged() {
        guard let game = selectedGame else { return }
        if viewModel.librarySelection.selectedGameID != game.id {
            viewModel.librarySelection.selectedGameID = game.id
        }
        if settings.settings.lastSelectedGameID != game.id {
            settings.settings.lastSelectedGameID = game.id
        }
        viewModel.loadStoreMetadata(for: game)
    }

    // MARK: - Art

    private var heroTaskKey: String {
        guard let game = selectedGame else { return "none" }
        let meta = viewModel.storeMetadata[game.id]
        let remote = meta?.headerImageURL ?? meta?.imageURL
        return "\(game.id)|\(remote?.absoluteString ?? "")|\(settings.settings.steamGridDbApiKey)"
    }

    private var logoTaskKey: String {
        guard let game = selectedGame else { return "none" }
        let remote = viewModel.storeMetadata[game.id]?.logoURL
        return "\(game.id)|\(remote?.absoluteString ?? "")|\(settings.settings.steamGridDbApiKey)"
    }

    /// The art changes after a 150 ms settle (a held stick does not load every
    /// game it passes), then crossfades.
    @MainActor
    private func loadHero() async {
        guard let game = selectedGame else {
            heroImage = nil
            heroKey = "none"
            return
        }
        if heroKey.hasPrefix(game.id.uuidString) { return }
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled else { return }
        let image = await GameArtLoader.shared.hero(
            for: game, metadata: viewModel.storeMetadata[game.id], artwork: artwork,
            steamGridDB: viewModel.steamGridDB, apiKey: settings.settings.steamGridDbApiKey)
        guard !Task.isCancelled, selectedGame?.id == game.id else { return }
        heroImage = image
        heroKey = image.map { "\(game.id.uuidString)|\(ObjectIdentifier($0).hashValue)" } ?? "none"
    }

    @MainActor
    private func loadLogo() async {
        guard let game = selectedGame, GameArtLoader.shared.cachedLogo(for: game) == nil else { return }
        let image = await GameArtLoader.shared.logo(
            for: game, metadata: viewModel.storeMetadata[game.id], artwork: artwork,
            steamGridDB: viewModel.steamGridDB, apiKey: settings.settings.steamGridDbApiKey)
        guard image != nil, !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { logoTick += 1 }
    }
}
