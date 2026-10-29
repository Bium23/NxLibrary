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
    @ObservedObject var runningGames: RunningGameMonitor
    @ObservedObject var artwork: ArtworkStore

    @Environment(\.seleneCanvas) var canvas

    @StateObject var art = SeleneHeroArt()
    @State var keyMonitor: Any?
    @State var hadGames = false
    /// The card Y menu: which card and the focused row.
    @State var cardMenu: CardMenuState?
    /// The open screenshot viewer (the game's titleID, its urls and the paging state).
    @State var viewer: ViewerContext?
    /// The filter pill: shown while the filter is not All, and for 1.2 s after switching to All.
    @State var pillFilter: LibraryFilter = .all
    @State var pillVisible = false
    @State var pillTask: Task<Void, Never>?

    struct ViewerContext: Equatable {
        var titleID: String
        var urls: [URL]
        var state: ScreenshotViewerState
    }

    struct CardMenuState: Equatable {
        var card: SpotlightCard
        var index = 0
    }

    init(viewModel: AppViewModel, router: AppRouter, settings: AppSettingsStore,
         playSessions: PlaySessionStore, runningGames: RunningGameMonitor,
         artwork: ArtworkStore) {
        self.viewModel = viewModel
        self.router = router
        self.settings = settings
        self.playSessions = playSessions
        self.runningGames = runningGames
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
                           order: viewModel.spotlight.lift?.order ?? settings.settings.spotlightOrder)
    }

    var selectedItem: SpotlightItem? { viewModel.spotlight.selectedItem(in: items) }

    var selectedGame: PortedGame? {
        guard case .game(let id) = selectedItem else { return nil }
        return viewModel.libraryGames.first { $0.id == id }
    }

    /// Everything one render needs, computed once per body.
    struct Snapshot {
        let items: [SpotlightItem]
        let gamesByID: [UUID: PortedGame]
        let selectedItem: SpotlightItem?
        let selectedGame: PortedGame?
    }

    private func snapshot() -> Snapshot {
        let items = self.items
        let gamesByID = Dictionary(viewModel.libraryGames.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let item = viewModel.spotlight.selectedItem(in: items)
        var game: PortedGame?
        if case .game(let id) = item { game = gamesByID[id] }
        return Snapshot(items: items, gamesByID: gamesByID, selectedItem: item, selectedGame: game)
    }

    var screenshotCount: Int {
        guard let game = selectedGame else { return 0 }
        let urls = viewModel.storeMetadata[game.id]?.screenshotURLs ?? []
        return min(urls.count, SpotlightScreenshotStrip.maxCount)
    }

    // MARK: - Body

    public var body: some View {
        let model = snapshot()
        let state = viewModel.spotlight
        ZStack(alignment: .topLeading) {
            SeleneArtBackground(image: art.image, imageKey: art.key,
                                shade: settings.settings.backgroundShade)
            stage(model, state: state)
                .frame(width: canvas.stageSize.width, height: canvas.stageSize.height, alignment: .topLeading)
                .offset(x: canvas.stageOrigin.x, y: canvas.stageOrigin.y)
        }
        .overlay(viewerOverlay)
        .animation(.easeOut(duration: 0.2), value: viewer != nil)
        .frame(width: canvas.size.width, height: canvas.size.height, alignment: .topLeading)
        .clipped()
        .onAppear(perform: appear)
        .onDisappear {
            removeKeyMonitor()
            router.isScreenshotViewerOpen = false
            pillTask?.cancel()
            mutate { $0.cancelLift() }
        }
        .onChange(of: viewModel.libraryGames) { _ in gamesChanged() }
        .onChange(of: filter) { newFilter in
            reconcile()
            filterChanged(to: newFilter)
        }
        .onChange(of: settings.settings.spotlightCards) { _ in reconcile() }
        .onChange(of: settings.settings.spotlightOrder) { _ in reconcile() }
        .onChange(of: viewModel.spotlight.selectedKey) { _ in selectionChanged() }
        .onChange(of: viewer != nil) { router.isScreenshotViewerOpen = $0 }
        .onChange(of: router.pendingSpotlightMove) { _ in consumePendingMove() }
        .onReceive(NotificationCenter.default.publisher(for: .nxFindGameSelect)) { note in
            guard let id = note.object as? UUID else { return }
            // Find a game lands on Spotlight; a tab without the game gives way to All games.
            let key = SpotlightItem.game(id).key
            if !items.contains(where: { $0.key == key }) { setFilter(.all) }
            mutate {
                $0.selectedKey = key
                $0.focus = .row
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxSpotlightGamepadAction)) { note in
            guard viewModel.alertMessage == nil else { return }
            if let action = note.object as? GamepadAction { handle(action) }
        }
        .onChange(of: playSessions.sessions.count) { _ in reconcile() }
        .task(id: art.heroTaskKey(model.selectedGame, metadata: model.selectedGame.flatMap { viewModel.storeMetadata[$0.id] },
                                  apiKey: settings.settings.steamGridDbApiKey)) { await loadHero(model.selectedGame) }
        .task(id: art.logoTaskKey(model.selectedGame, metadata: model.selectedGame.flatMap { viewModel.storeMetadata[$0.id] },
                                  apiKey: settings.settings.steamGridDbApiKey)) { await loadLogo(model.selectedGame) }
    }

    @ViewBuilder
    private var viewerOverlay: some View {
        if let viewer {
            ScreenshotViewer(titleID: viewer.titleID, urls: viewer.urls, state: viewer.state,
                             artwork: artwork, onClose: closeViewer)
                .transition(.opacity)
        }
    }

    private func stage(_ model: Snapshot, state: SpotlightState) -> some View {
        let items = model.items
        return ZStack(alignment: .topLeading) {
            SpotlightTopBar(filter: filter, showClock: settings.settings.showClock,
                            onSelect: { if !state.isLifted { setFilter($0) } })

            SpotlightRowView(
                items: items,
                gamesByID: model.gamesByID,
                selectedKey: state.selectedKey,
                liftedKey: state.lift?.key,
                isEmptyFilter: items.contains { if case .game = $0 { return true } else { return false } }
                    ? nil : filter,
                steamGridDbApiKey: settings.settings.steamGridDbApiKey,
                artwork: artwork,
                steamGridDB: viewModel.steamGridDB,
                coverURL: { viewModel.storeMetadata[$0.id]?.imageURL },
                onSelect: { item in
                    guard !state.isLifted else { return }
                    mutate { $0.select(item) }
                },
                onActivate: { item in
                    guard !state.isLifted else { return }
                    mutate { $0.select(item) }
                    activate(item)
                }
            )
            .offset(y: canvas.u(130))

            SpotlightFilterPill(filter: pillFilter, count: games.count)
                .offset(x: canvas.u(80), y: canvas.u(88))
                // Opacity fades always run, reduce motion or not.
                .opacity(pillVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: pillVisible)

            info(model, state: state)
                .offset(x: canvas.u(80), y: canvas.u(420))

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                SeleneHintsBar(left: state.isLifted || cardMenu != nil ? [] : globalHints,
                               right: contextHints(model, state), bottom: 40, leftInset: 18)
            }

            if let menu = cardMenu {
                ZStack {
                    Color.black.opacity(0.45)
                        .contentShape(Rectangle())
                        .onTapGesture { cardMenu = nil }
                    SpotlightCardMenu(card: menu.card, focusedIndex: menu.index,
                                      onFocus: { cardMenu?.index = $0 },
                                      onChoose: { chooseCardMenu($0) })
                }
                .frame(width: canvas.stageSize.width, height: canvas.stageSize.height)
                .transition(.opacity)
                .zIndex(5)
            }
        }
    }

    @ViewBuilder
    private func info(_ model: Snapshot, state: SpotlightState) -> some View {
        if let game = model.selectedGame {
            let metadata = viewModel.storeMetadata[game.id]
            VStack(alignment: .leading, spacing: 0) {
                SpotlightGameInfoView(
                    game: game,
                    logo: logo(for: game),
                    presentation: LibraryPresentation(
                        game: game, metadata: metadata,
                        totalPlaytime: playSessions.totalDuration(for: game.id),
                        lastPlayed: playSessions.lastPlayed(for: game.id)),
                    isRunning: runningGames.isRunning(game),
                    focusedPill: state.focus == .pills ? state.pillIndex : nil,
                    onPill: { index in
                        guard !state.isLifted else { return }
                        mutate { $0.focus = .pills; $0.pillIndex = index }
                        pressPill(index, game: game)
                    },
                    onHoverPill: { index in
                        guard !state.isLifted else { return }
                        mutate { $0.focus = .pills; $0.pillIndex = index }
                    }
                )
                .id(game.id)

                SpotlightScreenshotStrip(
                    titleID: game.titleId ?? game.uniqueKey,
                    urls: metadata?.screenshotURLs ?? [],
                    known: screenshotsKnown(game, metadata: metadata),
                    focusedIndex: state.focus == .strip ? state.stripIndex : nil,
                    artwork: artwork,
                    onSelect: { index in
                        guard !state.isLifted else { return }
                        mutate { $0.focus = .strip; $0.stripIndex = index }
                        openViewer(at: index)
                    }
                )
                .padding(.top, canvas.u(34))
            }
        } else if case .card(let card) = model.selectedItem {
            let summary = card == .activity ? activitySummary : ActivitySummary()
            let top = summary.topGames.compactMap { model.gamesByID[$0] }.filter { !$0.isHidden }
            let visible = viewModel.libraryGames.filter { !$0.isHidden }
            // Selene's card panels sit 40 under the row, 10 lower than a game's.
            SpotlightCardInfoView(
                card: card,
                gameCount: visible.count,
                installedCount: visible.filter(\.isPlayableLocally).count,
                poolLabel: Self.poolLabel(settings.settings.surprisePool),
                activity: summary,
                topGames: top,
                focusedTop: state.focus == .topGames ? state.topGameIndex : nil,
                steamGridDbApiKey: settings.settings.steamGridDbApiKey,
                artwork: artwork,
                steamGridDB: viewModel.steamGridDB,
                coverURL: { viewModel.storeMetadata[$0.id]?.imageURL },
                onTopGame: { index in
                    guard !state.isLifted, index < top.count else { return }
                    selectGame(top[index].id)
                }
            )
            .padding(.top, canvas.u(10))
        }
    }

    static func poolLabel(_ pool: SurprisePool) -> String {
        switch pool {
        case .installed: return "Installed games"
        case .notPlayed: return "Games not played yet"
        case .all: return "All games"
        }
    }

    /// This week's play time. The week is Monday-first (see `Activity.summary`).
    var activitySummary: ActivitySummary {
        Activity.summary(sessions: playSessions.sessions, now: Date(), calendar: Calendar.current)
    }

    /// Top-game ids that still exist as visible games, in order.
    var topGameCount: Int {
        guard selectedItem == .card(.activity) else { return 0 }
        return visibleTopGameIDs.count
    }

    /// Top-game ids that exist and are not hidden, in order.
    var visibleTopGameIDs: [UUID] {
        let known = Set(viewModel.libraryGames.filter { !$0.isHidden }.map(\.id))
        return activitySummary.topGames.filter(known.contains)
    }

    /// "No screenshots" only once the answer is final: not before the first
    /// request starts, nor while a stale empty cache entry is being refetched.
    private func screenshotsKnown(_ game: PortedGame, metadata: NintendoStoreMetadata?) -> Bool {
        if viewModel.storeMetadataLoading.contains(game.id) { return false }
        guard let titleId = game.titleId, !titleId.isEmpty else { return true }
        return metadata != nil || viewModel.storeMetadataErrors[game.id] != nil
    }

    private func logo(for game: PortedGame) -> NSImage? {
        art.logo(for: game)
    }

    // MARK: - Hints

    private var globalHints: [HintItem] {
        [HintItem(nil, "Collection", glyph: .spotlight, hold: "Hold: Search"),
         HintItem(nil, "Menu", glyph: .menu, hold: "Hold: Settings")]
    }

    private func contextHints(_ model: Snapshot, _ state: SpotlightState) -> [HintItem] {
        if state.isLifted {
            return [HintItem(nil, "◂ ▸  Move"), HintItem(.a, "Drop"), HintItem(.b, "Cancel")]
        }
        if cardMenu != nil {
            return [HintItem(.a, "Select"), HintItem(.b, "Back")]
        }
        switch state.focus {
        case .pills:
            return [HintItem(.a, "Select")]
        case .strip:
            return []
        case .topGames:
            return [HintItem(.a, "Show")]
        case .row:
            switch model.selectedItem {
            case .card(let card):
                let more = [HintItem(.y, "Card options")]
                return card == .activity ? more : more + [HintItem(.a, card == .surprise ? "Pick" : "Open")]
            case .game:
                guard let game = model.selectedGame else { return [] }
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
        router.isSearchPresented = false
        viewModel.preloadCachedStoreMetadata()
        if !viewModel.spotlight.startingTabApplied {
            mutate { $0.startingTabApplied = true }
            viewModel.librarySelection.query.filter = LibraryFilter(startingTab: settings.settings.startingTab)
        }
        hadGames = !viewModel.libraryGames.isEmpty
        reconcile()
        selectionChanged()
        pillFilter = filter
        pillVisible = filter != .all
        consumePendingMove()
        consumePendingSelect()
    }

    /// Shows the pill for any filter but All; switching to All flashes it for 1.2 s.
    private func filterChanged(to next: LibraryFilter) {
        pillTask?.cancel()
        pillFilter = next
        pillVisible = true
        guard next == .all else { return }
        pillTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            pillVisible = false
        }
    }

    /// Selects the item whose Move was requested and lifts it.
    func consumePendingMove() {
        guard let key = router.pendingSpotlightMove else { return }
        router.pendingSpotlightMove = nil
        if !items.contains(where: { $0.key == key }), filter != .all {
            viewModel.librarySelection.query.filter = .all
        }
        let items = self.items
        guard let item = items.first(where: { $0.key == key }) else { return }
        cardMenu = nil
        mutate { state in
            state.cancelLift()
            state.select(item)
            state.beginLift(in: items)
        }
        SoundEffectService.shared.play(.click)
    }

    private func gamesChanged() {
        viewModel.preloadCachedStoreMetadata()
        // The whole library, not the filtered row: a filter change never
        // counts as "the library arrived".
        let hasGames = !viewModel.libraryGames.isEmpty
        // The library loads after the first frame: a card picked while it was
        // empty gives way to the restored (or first) game.
        if !hadGames, hasGames, case .card = selectedItem {
            mutate { $0.selectedKey = nil }
        }
        hadGames = hasGames
        reconcile()
    }

    func reconcile() {
        // The lifted tile vanished (library reload, settings change): put it back.
        if let lifted = viewModel.spotlight.lift?.key, !items.contains(where: { $0.key == lifted }) {
            mutate { $0.cancelLift() }
        }
        let preferred = settings.settings.restoreLastGame ? settings.settings.lastSelectedGameID : nil
        let items = self.items
        mutate { $0.reconcile(with: items, preferredGameID: preferred) }
    }

    func setFilter(_ next: LibraryFilter) {
        guard next != filter else { return }
        viewModel.librarySelection.query.filter = next
        mutate { $0.focus = .row }
        reconcile() // Same frame: the selection is never missing from the row.
        SoundEffectService.shared.play(.tabSwitch)
    }

    private func selectionChanged() {
        guard let game = selectedGame else { return }
        if settings.settings.lastSelectedGameID != game.id {
            settings.settings.lastSelectedGameID = game.id
        }
        viewModel.loadStoreMetadata(for: game)
    }

    // MARK: - Art

    private func loadHero(_ game: PortedGame?) async {
        await art.loadHero(game: game, current: { selectedGame?.id },
                           metadata: game.flatMap { viewModel.storeMetadata[$0.id] }, artwork: artwork,
                           steamGridDB: viewModel.steamGridDB, apiKey: settings.settings.steamGridDbApiKey)
    }

    private func loadLogo(_ game: PortedGame?) async {
        await art.loadLogo(game: game, metadata: game.flatMap { viewModel.storeMetadata[$0.id]},
                           artwork: artwork, steamGridDB: viewModel.steamGridDB,
                           apiKey: settings.settings.steamGridDbApiKey)
    }
}
