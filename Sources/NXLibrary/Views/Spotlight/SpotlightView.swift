import SwiftUI
import AppKit
import NXLibraryCore

/// Spotlight, the home screen (spec §5.2, Selene Main.xaml HOME): one row of
/// square tiles under the filter tabs, the selected game's logo, pills and
/// stats, its screenshots, over its art. All lengths are Selene units on the
/// 1920 × 1080 stage that `SeleneHomeChrome` places (pinned to the top, hints on
/// the window's bottom edge), shared with Collection. The backdrop and the row
/// reach the window edges.
///
/// Below the stats the screen is one page: genres, screenshots, the
/// description with Details beside it, More like this. Down
/// from the row shifts everything up (the row and the bar fade away, the logo
/// rises to the top) and keeps going section by section; Up comes back.
struct SpotlightView: View {
    @ObservedObject var viewModel: AppViewModel
    /// The Setup (`SetupModel`): Rebuild follows the Metal gate.
    @ObservedObject var setup: SetupModel
    /// The Nintendo store's data (`StoreMetadataModel`): descriptions, screenshots and names shown here.
    @ObservedObject var store: StoreMetadataModel
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var playSessions: PlaySessionStore
    /// Steam Play phases drive the A hint.
    @ObservedObject var steamPlayer = SteamPlayCoordinator.shared
    @ObservedObject var runningGames: RunningGameMonitor
    @ObservedObject var artwork: ArtworkStore

    @Environment(\.seleneCanvas) var canvas
    @Environment(\.seleneReduceMotion) var reduceMotion
    @Environment(\.nxAppLocale) var localization

    @StateObject var art = SeleneHeroArt()
    /// Art the player picks redraws the hero and logo (their task keys carry its revision).
    @ObservedObject var picks = ArtworkPicks.shared
    /// Steam store facts and personal fields, shared with the Steam head.
    @ObservedObject var steamFacts = SteamGameFacts.shared
    @ObservedObject var achievementsStore = SteamAchievementsStore.shared
    @ObservedObject var steamFields = SteamPersonalizations.shared.metadata
    /// Only traits are retained for the cache pass, without artwork, screenshots or descriptions.
    @State var cachedSteamRelated: (request: SteamRelatedRequest, traits: [UInt32: MoreLikeThis.Traits])?
    @State var keyMonitor: Any?
    @State var hadGames = false
    /// The card Y menu: which card and the focused row.
    @State var cardMenu: CardMenuState?
    /// The open screenshot viewer (the game's titleID, its urls and the paging state).
    @State var viewer: ViewerContext?
    /// The open Achievements screen's selection; the game is the selected Steam game.
    @State var achievementsScreen: AchievementsScreenModel?
    /// The filter pill: shown while the filter is not All, and for 1.2 s after switching to All.
    @State var pillFilter: LibraryFilter = .all
    @State var pillVisible = false
    @State var pillTask: Task<Void, Never>?
    /// The game column's block heights (`SpotlightPageBlock`), which place the page's scroll.
    @State var blocks: [SpotlightPageBlock: CGFloat] = [:]
    /// The page's scroll and fades, moved in their own transactions (`syncPage`) so
    /// nothing inside (a pill's focus, say) rides a faster curve than the page.
    @State var scroll: CGFloat = 0
    @State var rowShown = true
    @State var belowShown = false
    @State var dimmed = false
    /// The screenshots' bottom fade has lifted (off the row).
    @State var stripFull = false
    /// A wheel gesture already moved between the row and the page: its remaining
    /// events (momentum included) are ignored until a new gesture starts.
    @State var wheelLocked = false
    /// Until when the page is gliding; pointer hovers are ignored meanwhile.
    @State var glideEnds = Date.distantPast
    /// The next focus change came from a wheel scroll: keep the page where it is.
    @State var holdScroll = false
    @State var wheelSettle: Task<Void, Never>?
    /// About this game shows its whole text (Read more); closes with the game.
    @State var aboutExpanded = false
    /// About this game shows Read more, as last drawn (`SpotlightReadMoreKey`).
    @State var aboutReadMore = false
    /// Wikipedia's introduction for the selected page, when its store text is in another language (`WikipediaAbout`).
    @State var wikipediaAbout: WikipediaAbout?
    /// The selected game's Mods band (installed mods, GameBanana's, their panels); shared with Details.
    @StateObject var modsHost = ModsBandHost()
    /// The Mods card's store, below the card.
    @ObservedObject var storeHost: ModStoreHost
    /// The backdrop's gold (`updateModsBackdrop`).
    @State var modsBackdrop = false
    /// Whether the previous game's art may stay while the next game's loads (`shownArt`).
    @State var artRule = BackdropArtRule()
    /// The wheel's travel inside the store, toward the next section.
    @State var storeWheel: CGFloat = 0
    /// The first home's entrance (`SpotlightView+Entrance`); landed on every later visit.
    @State var entrance: SpotlightEntrance.Phase
    /// Visible tiles still looking up their first art (`TileArtPendingKey`).
    @State var pendingTileArt = 0
    /// The entrance's longest wait for the tiles' art.
    @State var entranceWait: Task<Void, Never>?
    /// The top bar and the button hints, held until the entrance has landed (`finishEntrance`).
    @State var controlsShown: Bool
    /// The breath on the moving moonlight is over (`SpotlightEntrance.hold`).
    @State var entranceBreathed = false
    var isGliding: Bool { Date() < glideEnds }

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
         artwork: ArtworkStore, storeHost: ModStoreHost) {
        self.viewModel = viewModel
        self.setup = viewModel.setup
        self.store = viewModel.store
        self.router = router
        self.settings = settings
        self.playSessions = playSessions
        self.runningGames = runningGames
        self.artwork = artwork
        self.storeHost = storeHost
        // Held hidden from the first frame (the opening, or under the welcome); `entranceAppear` lands it when not due.
        _entrance = State(initialValue: viewModel.homeSeen ? .landed : .covered)
        _controlsShown = State(initialValue: viewModel.homeSeen)
    }

    // MARK: - Model

    var filter: LibraryFilter { viewModel.librarySelection.query.filter }

    /// The filtered, visible games, most recently played first.
    var games: [PortedGame] {
        LibraryQuery(filter: filter).apply(to: viewModel.libraryGames, history: playSessions)
    }

    var rowGames: [CatalogGame] {
        LibraryQuery(filter: filter).applyCatalog(to: viewModel.visibleCatalogGames, history: playSessions)
    }
    var selectedCatalogGame: CatalogGame? {
        guard case .game(let id) = selectedItem else { return nil }
        return viewModel.visibleCatalogGames.first { $0.id == id }
    }
    var items: [SpotlightItem] { rowItems(for: rowGames) }

    private func rowItems(for games: [CatalogGame]) -> [SpotlightItem] {
        let ids = games.map(\.id)
        return SpotlightRow.build(gameIDs: ids,
                                  enabledCards: settings.settings.visibleSpotlightCards,
                                  order: viewModel.spotlight.lift?.order ?? settings.settings.spotlightOrder,
                                  front: SpotlightRow.leaders(porting: viewModel.frontGameID,
                                                              downloads: viewModel.sessionDownloads.ids, row: ids))
    }

    var selectedItem: SpotlightItem? { viewModel.spotlight.selectedItem(in: items) }

    var selectedGame: PortedGame? {
        guard case .game(let id) = selectedItem else { return nil }
        return viewModel.libraryGames.first { $0.id == id }
    }

    /// Everything one render needs, computed once per body.
    struct Snapshot {
        let items: [SpotlightItem]
        let rowGameCount: Int
        let gamesByID: [UUID: PortedGame]
        let selectedItem: SpotlightItem?
        let selectedGame: PortedGame?
        let catalogGamesByID: [UUID: CatalogGame]
        let selectedCatalogGame: CatalogGame?
    }

    private func snapshot() -> Snapshot {
        let visible = viewModel.visibleCatalogGames
        let rowGames = LibraryQuery(filter: filter).applyCatalog(to: visible, history: playSessions)
        let items = rowItems(for: rowGames)
        let gamesByID = Dictionary(viewModel.libraryGames.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let item = viewModel.spotlight.selectedItem(in: items)
        let catalog = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let id: UUID?
        if case .game(let selected) = item { id = selected } else { id = nil }
        return Snapshot(items: items, rowGameCount: rowGames.count, gamesByID: gamesByID, selectedItem: item,
                        selectedGame: id.flatMap { gamesByID[$0] }, catalogGamesByID: catalog,
                        selectedCatalogGame: id.flatMap { catalog[$0] })
    }

    /// One pill while the selected game ports, three otherwise.
    var selectedPillCount: Int {
        selectedGame.map { viewModel.portingPills($0).count } ?? SpotlightState.pillCount
    }

    var screenshotCount: Int {
        if let game = selectedCatalogGame, game.integration == .steam {
            return min(steamFacts.metadata(for: game)?.screenshots.count ?? 0, SpotlightScreenshotStrip.maxCount)
        }
        guard let game = selectedGame else { return 0 }
        let urls = store.storeMetadata[game.id]?.screenshotURLs ?? []
        return min(urls.count, SpotlightScreenshotStrip.maxCount)
    }

    // MARK: - Body

    // The body is split in steps: one chain of every modifier is more than the type checker can solve in time.
    var body: some View {
        let model = snapshot()
        tasks(model, on: events(on: libraryChanges(on: lifecycle(on: chrome(model, state: viewModel.spotlight)))))
    }

    private func chrome(_ model: Snapshot, state: SpotlightState) -> some View {
        SeleneHomeChrome(
            leftHints: state.isLifted || cardMenu != nil || state.focus != .row
                ? [] : HintItem.homeGlobals(other: "Collection",
                                            onOther: { if settings.settings.viewButtonSwitches { router.openCollection() } },
                                            onMenu: { router.isMenuPresented = true }),
            rightHints: contextHints(model, state),
            rightReserve: hintReserve(state),
            hintsHidden: router.overlayHasHints(viewModel) || achievementsScreen != nil,
            hintsHeld: !controlsShown,
            backdrop: {
                // On a card no art; on the Mods card the moonlight glides to gold (and stays gold until the next
                // game's art has arrived, so leaving the card is one change, not gold → blue → art).
                let shown = shownArt(model)
                SeleneArtBackground(image: shown, imageKey: shown == nil ? "none" : art.key,
                                    shade: settings.settings.backgroundShade, crossfade: 0.8,
                                    showsArt: !settings.settings.keepWallpaperOnGames, modsTint: modsBackdrop,
                                    reveal: artReveal)
                // Deeper in the page the art dims so the text reads.
                Color.black.opacity(dimmed ? 0.4 : 0)
                    .allowsHitTesting(false)
            },
            stage: { stage(model, state: state) })
        .overlay(viewerOverlay)
        .animation(.easeOut(duration: 0.2), value: viewer != nil)
        .overlay(achievementsOverlay(model))
        .animation(SeleneTheme.screen, value: achievementsScreen != nil)
        .overlay(model.selectedGame.map { ModsBandOverlay(host: modsHost, find: modsHost.find, game: $0) })
        .overlay(storeOverlay(model))
    }

    /// Appearing, the entrance, the pills and the Achievements screen, and leaving.
    private func lifecycle(on content: some View) -> some View {
        content
        .onAppear(perform: appear)
        .onAppear(perform: entranceAppear)
        .onChange(of: isCovered) { _, covered in if !covered { uncoverEntrance() } }
        .onChange(of: reduceMotion) { _, reduced in if reduced { landEntrance() } }
        // A resize mid-flight lands it; before the flight the starts follow the window (the launch can still size it).
        .onChange(of: canvas) { if entrance == .playing { landEntrance() } }
        .onAppear { storeHost.loadCover(titleIDs: Set(storeGames.compactMap { viewModel.modStore(for: $0)?.titleID })) }
        .onAppear { mutate { $0.setPillLimit(selectedPillCount) } }
        .onChange(of: selectedPillCount) { _, count in mutate { $0.setPillLimit(count) } }
        // A re-read can remove the tile (the files went away): the focus leaves it for the screenshots.
        .onChange(of: selectedAchievements == nil) { _, gone in
            guard gone else { return }
            achievementsScreen = nil
            guard viewModel.spotlight.focus == .achievements else { return }
            mutate { $0.focus = screenshotCount > 0 ? .strip : .pills }
        }
        // A re-read while the screen is open: the selection stays inside the list.
        .onChange(of: selectedAchievements) { _, summary in
            guard let summary, let screen = achievementsScreen else { return }
            screen.setIDs(summary.rows(screen.state.filter, order: screen.state.order).map(\.id))
        }
        // Another game, or the row: the screen belongs to the game it opened on.
        .onChange(of: viewModel.spotlight.selectedKey) { achievementsScreen = nil }
        .onDisappear {
            landEntrance()
            removeKeyMonitor()
            router.isScreenshotViewerOpen = false
            achievementsScreen = nil
            modsHost.stop()
            storeHost.close()
            pillTask?.cancel()
            mutate { $0.cancelLift() }
        }
    }

    /// The library, the filter, the selection and the page.
    private func libraryChanges(on content: some View) -> some View {
        content
        .onChange(of: viewModel.catalogGames) { gamesChanged() }
        .onChange(of: viewModel.catalogSourceConfigurations) { gamesChanged() }
        .onChange(of: filter) { _, newFilter in
            reconcile()
            filterChanged(to: newFilter)
        }
        .onChange(of: settings.settings.visibleSpotlightCards) { reconcile() }
        .onChange(of: settings.settings.spotlightOrder) { reconcile() }
        .onChange(of: viewModel.spotlight.selectedKey) {
            aboutExpanded = false
            selectionChanged()
        }
        .onChange(of: viewModel.spotlight.focus) { _, focus in
            syncPage()
            startModsOnline(focus)
        }
        // Game options (its Mods panel) closing, or Arcane coming back from Finder, re-reads the mods.
        .onChange(of: !viewModel.isGameOptionsOpen) { _, closed in if closed { reloadMods() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reloadMods() }
        .onChange(of: blocks) { syncPage() }
        // Inside the store the page glides section to section on a shorter curve.
        .onChange(of: storeHost.focus) { syncPage(glide: Self.storeGlide) }
        .onChange(of: storeHost.sections.map(\.kind)) { syncPage(glide: Self.storeGlide) }
        // The viewer and the Achievements screen both keep the shell's own buttons away.
        .onChange(of: viewer != nil || achievementsScreen != nil) { router.isScreenshotViewerOpen = $1 }
        .onChange(of: router.pendingSpotlightMove) { consumePendingMove() }
    }

    /// Find a game and the controller.
    private func events(on content: some View) -> some View {
        content
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
            // The welcome's fade: the controller reaches Spotlight only once it has gone.
            guard viewModel.alertMessage == nil, viewModel.settingsNotice == nil, !isOverlaid else { return }
            if let action = note.object as? GamepadAction { handle(action) }
        }
    }

    /// Play history and the art of the selected game.
    private func tasks(_ model: Snapshot, on content: some View) -> some View {
        content
        .onChange(of: playSessions.sessions.count) { reconcile() }
        .task(id: art.heroTaskKey(model.selectedGame, metadata: model.selectedGame.flatMap { store.storeMetadata[$0.id] })) { await loadHero(model.selectedGame) }
        .task(id: art.steamHeroTaskKey(model.selectedCatalogGame)) {
            await art.loadSteamHero(game: model.selectedCatalogGame, current: { selectedCatalogGame?.id }, artwork: artwork, settle: 420_000_000)
            if model.selectedCatalogGame?.integration == .steam, !Task.isCancelled { modsBackdrop = false }
        }
        .task(id: art.logoTaskKey(model.selectedGame, metadata: model.selectedGame.flatMap { store.storeMetadata[$0.id] })) { await loadLogo(model.selectedGame) }
    }

}
