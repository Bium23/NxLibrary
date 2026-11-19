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
public struct SpotlightView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var playSessions: PlaySessionStore
    /// Steam Play phases drive the A hint.
    @ObservedObject var steamPlayer = SteamPlayCoordinator.shared
    @ObservedObject var runningGames: RunningGameMonitor
    @ObservedObject var artwork: ArtworkStore

    @Environment(\.seleneCanvas) var canvas
    @Environment(\.seleneReduceMotion) var reduceMotion
    @Environment(\.nxAppLocale) private var localization

    @StateObject var art = SeleneHeroArt()
    /// Art the player picks redraws the hero and logo (their task keys carry its revision).
    @ObservedObject var picks = ArtworkPicks.shared
    /// Steam store facts and personal fields, shared with the Steam head.
    @ObservedObject var steamFacts = SteamGameFacts.shared
    @ObservedObject var achievementsStore = SteamAchievementsStore.shared
    @ObservedObject var steamFields = SteamPersonalizations.shared.metadata
    /// Only traits are retained for the cache pass, without artwork, screenshots or descriptions.
    @State private var cachedSteamRelated: (request: SteamRelatedRequest, traits: [UInt32: MoreLikeThis.Traits])?
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
    /// Translate in About this game (`DescriptionTranslator`).
    @ObservedObject var translator = DescriptionTranslator.shared
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
        let urls = viewModel.storeMetadata[game.id]?.screenshotURLs ?? []
        return min(urls.count, SpotlightScreenshotStrip.maxCount)
    }

    // MARK: - Body

    public var body: some View {
        let model = snapshot()
        let state = viewModel.spotlight
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
        .onAppear(perform: appear)
        .onAppear(perform: entranceAppear)
        .onChange(of: isCovered) { covered in if !covered { uncoverEntrance() } }
        .onChange(of: reduceMotion) { reduced in if reduced { landEntrance() } }
        // A resize mid-flight lands it; before the flight the starts follow the window (the launch can still size it).
        .onChange(of: canvas) { _ in if entrance == .playing { landEntrance() } }
        .onAppear { storeHost.loadCover(titleIDs: Set(storeGames.compactMap { viewModel.modStore(for: $0)?.titleID })) }
        .onAppear { mutate { $0.setPillLimit(selectedPillCount) } }
        .onChange(of: selectedPillCount) { count in mutate { $0.setPillLimit(count) } }
        // A re-read can remove the tile (the files went away): the focus leaves it for the screenshots.
        .onChange(of: selectedAchievements == nil) { gone in
            guard gone else { return }
            achievementsScreen = nil
            guard viewModel.spotlight.focus == .achievements else { return }
            mutate { $0.focus = screenshotCount > 0 ? .strip : .pills }
        }
        // A re-read while the screen is open: the selection stays inside the list.
        .onChange(of: selectedAchievements) { summary in
            guard let summary, let screen = achievementsScreen else { return }
            screen.setIDs(summary.rows(screen.state.filter, order: screen.state.order).map(\.id))
        }
        // Another game, or the row: the screen belongs to the game it opened on.
        .onChange(of: viewModel.spotlight.selectedKey) { _ in achievementsScreen = nil }
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
        .onChange(of: viewModel.catalogGames) { _ in gamesChanged() }
        .onChange(of: viewModel.catalogSourceConfigurations) { _ in gamesChanged() }
        .onChange(of: filter) { newFilter in
            reconcile()
            filterChanged(to: newFilter)
        }
        .onChange(of: settings.settings.visibleSpotlightCards) { _ in reconcile() }
        .onChange(of: settings.settings.spotlightOrder) { _ in reconcile() }
        .onChange(of: viewModel.spotlight.selectedKey) { _ in
            aboutExpanded = false
            selectionChanged()
        }
        .onChange(of: viewModel.spotlight.focus) { focus in
            syncPage()
            startModsOnline(focus)
        }
        // Game options (its Mods panel) closing, or NX Library coming back from Finder, re-reads the mods.
        .onChange(of: !viewModel.isGameOptionsOpen) { closed in if closed { reloadMods() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reloadMods() }
        .onChange(of: blocks) { _ in syncPage() }
        // Inside the store the page glides section to section on a shorter curve.
        .onChange(of: storeHost.focus) { _ in syncPage(glide: Self.storeGlide) }
        .onChange(of: storeHost.sections.map(\.kind)) { _ in syncPage(glide: Self.storeGlide) }
        // The viewer and the Achievements screen both keep the shell's own buttons away.
        .onChange(of: viewer != nil || achievementsScreen != nil) { router.isScreenshotViewerOpen = $0 }
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
            // The welcome's fade: the controller reaches Spotlight only once it has gone.
            guard viewModel.alertMessage == nil, viewModel.settingsNotice == nil, !isOverlaid else { return }
            if let action = note.object as? GamepadAction { handle(action) }
        }
        .onChange(of: playSessions.sessions.count) { _ in reconcile() }
        .task(id: art.heroTaskKey(model.selectedGame, metadata: model.selectedGame.flatMap { viewModel.storeMetadata[$0.id] })) { await loadHero(model.selectedGame) }
        .task(id: art.steamHeroTaskKey(model.selectedCatalogGame)) {
            await art.loadSteamHero(game: model.selectedCatalogGame, current: { selectedCatalogGame?.id }, artwork: artwork, settle: 420_000_000)
            if model.selectedCatalogGame?.integration == .steam, !Task.isCancelled { modsBackdrop = false }
        }
        .task(id: art.logoTaskKey(model.selectedGame, metadata: model.selectedGame.flatMap { viewModel.storeMetadata[$0.id] })) { await loadLogo(model.selectedGame) }
    }

    @ViewBuilder
    private func storeOverlay(_ model: Snapshot) -> some View {
        if model.selectedItem == .card(.mods), let game = storeHost.panel.game {
            ModsBandOverlay(host: storeHost.panel, find: storeHost.panel.find, game: game)
        }
    }

    @ViewBuilder
    private var viewerOverlay: some View {
        if let viewer {
            ScreenshotViewer(titleID: viewer.titleID, urls: viewer.urls, state: viewer.state,
                             artwork: artwork, onClose: closeViewer)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func achievementsOverlay(_ model: Snapshot) -> some View {
        if let screen = achievementsScreen, let game = model.selectedCatalogGame, let summary = selectedAchievements {
            AchievementsScreen(model: screen, game: game, summary: summary, art: shownArt(model),
                               onFilter: { filter in
                                   guard filter != screen.state.filter else { return }
                                   screen.setFilter(filter, summary: summary)
                                   SoundEffectService.shared.play(.tabSwitch)
                               },
                               onShiftFilter: { delta in
                                   screen.shiftFilter(by: delta, summary: summary)
                                   SoundEffectService.shared.play(.tabSwitch)
                               },
                               onCycleOrder: {
                                   screen.cycleOrder(summary: summary)
                                   SoundEffectService.shared.play(.tabSwitch)
                               },
                               onFocus: { index in
                                   // A click on the focused row opens it, as A does.
                                   guard index != screen.state.index else {
                                       if screen.openDetail() { SoundEffectService.shared.play(.click) }
                                       return
                                   }
                                   screen.focus(index)
                                   SoundEffectService.shared.play(.focus)
                               },
                               onOpen: { if screen.openDetail() { SoundEffectService.shared.play(.click) } },
                               onCloseDetail: {
                                   screen.closeDetail()
                                   SoundEffectService.shared.play(.focus)
                               },
                               onClose: closeAchievements)
                .transition(.opacity)
        }
    }

    private func stage(_ model: Snapshot, state: SpotlightState) -> some View {
        let items = model.items
        return ZStack(alignment: .topLeading) {
            SpotlightTopBar(filter: filter, showClock: settings.settings.showClock,
                            onSelect: { if !state.isLifted { setFilter($0) } })
                // Comes in last with the hints (`finishEntrance`).
                .opacity(rowShown && controlsShown ? 1 : 0)
                .allowsHitTesting(rowShown && entrance.takesInput)

            ZStack(alignment: .topLeading) {
                SpotlightRowView(
                    items: items,
                    gamesByID: model.gamesByID,
                    catalogGamesByID: model.catalogGamesByID,
                    selectedKey: state.selectedKey,
                    liftedKey: state.lift?.key,
                    isEmptyFilter: LibraryEmptyState.showsMessage(
                        hasGames: items.contains { if case .game = $0 { return true } else { return false } },
                        isReadingLibrary: viewModel.isScanningLibrary) ? filter : nil,
                    artwork: artwork,
                    tileLook: viewModel.portingTileLook,
                    modsCover: storeHost.cover,
                    entrance: entrance,
                    onEntranceEnd: { finishEntrance() },
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
                // The icons give way as the page rises (and stop taking the pointer).
                .opacity(rowOpacity)
                .allowsHitTesting(rowShown && entrance.takesInput)
                .onPreferenceChange(TileArtPendingKey.self, perform: tileArtPending)

                SpotlightFilterPill(filter: pillFilter, count: model.rowGameCount)
                    .offset(x: canvas.u(80), y: canvas.u(88))
                    // Opacity fades always run, reduce motion or not.
                    .opacity(pillVisible && !entrance.holdsHidden ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: pillVisible)
                    .animation(entranceRise, value: entrance.holdsHidden)

                info(model, state: state)
                    .offset(x: canvas.u(80), y: canvas.u(420))
                    .entrance(entrance == .landed ? nil : SpotlightEntrance.info, launched: entranceLaunched,
                              unit: canvas.u(1))
                    .allowsHitTesting(entrance.takesInput)
            }
            .onPreferenceChange(SpotlightBlockKey.self) { heights in
                if !Self.sameLayout(heights, blocks) { blocks = heights }
            }
            .onPreferenceChange(SpotlightReadMoreKey.self) { shown in
                if shown != aboutReadMore { aboutReadMore = shown }
            }
            // Every block rides the glide as one: the fades that run beside it (`setPageFades`) re-timed leaves
            // of their own and they slid at their own pace (`GlideGroup`).
            .modifier(GlideGroup())
            // One page: the focus scrolls it; the glide is movement, so reduce motion jumps.
            .offset(y: scroll)
            // The page fades out short of the window's edges, top and bottom.
            .frame(width: canvas.stageSize.width, height: canvas.size.height, alignment: .topLeading)
            .mask(pageMask)
            .contentShape(Path(CGRect(x: 0, y: 0, width: canvas.stageSize.width,
                                      height: max(0, canvas.size.height - canvas.u(SeleneBottomScrim.contentClearance)))))

            // Off the row, the page has risen: there is more above (More like this is the end).
            SpotlightUpHint()
                .frame(width: canvas.stageSize.width)
                .padding(.top, canvas.u(24))
                .opacity([.pills, .strip, .about, .actions, .store].contains(state.focus) ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: state.focus)
                .allowsHitTesting(false)

            if let menu = cardMenu {
                ZStack {
                    Color.black.opacity(0.45)
                        .contentShape(Rectangle())
                        .onTapGesture { cardMenu = nil }
                    SpotlightCardMenu(card: menu.card, focusedIndex: menu.index,
                                      onFocus: { cardMenu?.index = $0 },
                                      onChoose: { chooseCardMenu($0) })
                }
                .frame(width: canvas.stageSize.width, height: canvas.size.height)
                .transition(.opacity)
                .zIndex(5)
            }
        }
    }

    @ViewBuilder
    private func info(_ model: Snapshot, state: SpotlightState) -> some View {
        if let game = model.selectedGame {
            let metadata = viewModel.storeMetadata[game.id]
            let genres = GameGenre.list(metadata?.genres ?? [])
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
                        // Hover moves along the pills only once they have focus, and never
                        // mid-glide: the page moving under a still pointer is not a hover.
                        guard !state.isLifted, state.focus == .pills, !isGliding else { return }
                        mutate { $0.pillIndex = index }
                    },
                    pillSet: viewModel.portingPills(game),
                    etaText: viewModel.portingETAText,
                    onOpenLog: { viewModel.revealLog(for: game) }
                )
                .id(game.id)
                .spotlightBlock(.head)

                if !genres.isEmpty {
                    SpotlightGenreChips(genres: genres)
                        // They leave and come back with the pills, not stay while the rest changes.
                        .modifier(SpotlightInfoFollow())
                        .id(game.id)
                        .padding(.top, canvas.u(20))
                        .spotlightBlock(.genres)
                }

                screenshotStrip(id: game.id, titleID: viewModel.personalizationKey(for: game),
                                urls: metadata?.screenshotURLs ?? [],
                                known: screenshotsKnown(game, metadata: metadata), state: state)

                // The lower page is offscreen on the row. Build it only as the page rises.
                if belowShown { pageBelow(game, page: page(for: game), state: state).transition(.opacity) }
            }
        } else if let game = model.selectedCatalogGame, game.integration == .steam {
            let metadata = steamFacts.metadata(for: game)
            let genres = GameDetailPresentation.steamGenres(
                for: game, metadata: metadata,
                override: steamFields.value(titleID: game.personalizationReference.key, field: .genres))
            VStack(alignment: .leading, spacing: 0) {
                CatalogSteamInfo(game: game, totalPlaytime: playSessions.totalDuration(for: game.id),
                                 lastPlayed: playSessions.lastPlayed(for: game.id),
                                 focused: state.focus == .pills ? state.pillIndex : nil,
                                 onAction: { index in
                                     guard !state.isLifted else { return }
                                     mutate { $0.focus = .pills; $0.pillIndex = index }
                                     pressCatalogPill(index, game: game)
                                 },
                                 onHover: { index in
                                     guard !state.isLifted, state.focus == .pills, !isGliding else { return }
                                     mutate { $0.pillIndex = index }
                                 })
                    .id(game.id)
                    .spotlightBlock(.head)

                if !genres.isEmpty {
                    SpotlightGenreChips(genres: genres)
                        .modifier(SpotlightInfoFollow())
                        .id(game.id)
                        .padding(.top, canvas.u(20))
                        .spotlightBlock(.genres)
                }

                screenshotStrip(id: game.id, titleID: game.personalizationReference.key,
                                urls: metadata?.screenshots ?? [],
                                known: steamFacts.isKnown(game), state: state)

                if belowShown {
                    let request = SteamRelatedRequest(
                        appIDs: Set(model.catalogGamesByID.values.compactMap { $0.isHidden ? nil : $0.steamGame?.appID }),
                        language: SteamMetadata.language(localization.language))
                    steamPageBelow(steamPage(for: game), state: state)
                        .task(id: request) { await loadCachedSteamRelated(request) }
                        .transition(.opacity)
                }
            }
        } else if model.selectedItem == .card(.mods) {
            VStack(alignment: .leading, spacing: 0) {
                SpotlightCardInfoView(
                    card: .mods, gameCount: 0, installedCount: 0, poolLabel: "", activity: ActivitySummary(),
                    topGames: [], focusedTop: nil, artwork: artwork, onTopGame: { _ in },
                    modCounts: storeHost.counts)
                    .padding(.top, canvas.u(10))
                    .spotlightBlock(.head)
                ModStorePage(host: storeHost, catalog: storeHost.catalog, active: state.focus == .store)
                    .padding(.top, canvas.u(Self.storeGap))
                    // Hidden while the row has focus: it rises in with the page.
                    .opacity(belowShown ? 1 : 0)
            }
        } else if case .card(let card) = model.selectedItem {
            let summary = card == .activity ? activitySummary : ActivitySummary()
            let top = summary.topGames.compactMap { model.gamesByID[$0] }.filter { !$0.isHidden }
            let visible = viewModel.visibleCatalogGames
            // Selene's card panels sit 40 under the row, 10 lower than a game's.
            SpotlightCardInfoView(
                card: card,
                gameCount: visible.count,
                installedCount: LibraryQuery(filter: .installed).applyCatalog(to: visible, history: playSessions).count,
                poolLabel: Self.poolLabel(settings.settings.surprisePool),
                activity: summary,
                topGames: top,
                focusedTop: state.focus == .topGames ? state.topGameIndex : nil,
                artwork: artwork,
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
        case .installed: return L10n.text("Installed games")
        case .notPlayed: return L10n.text("Games not played yet")
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
        if viewModel.storeMetadataLoading.contains(game.id) || viewModel.screenshotLookups.contains(game.id) { return false }
        guard let titleId = game.titleId, !titleId.isEmpty else { return true }
        return metadata != nil || viewModel.storeMetadataErrors[game.id] != nil
    }

    private func logo(for game: PortedGame) -> NSImage? {
        art.logo(for: game)
    }

    // MARK: - Hints

    /// The A slot keeps one width per place (row, page), so the prompts hold still
    /// as the focus moves. Y and B sit leftmost, where a longer label shifts nothing.
    private func hintReserve(_ state: SpotlightState) -> [[String]] {
        if state.isLifted || cardMenu != nil { return [] }
        switch state.focus {
        case .row: return [[], ["Play", "Build", "Pick", "Open"]]
        case .pills, .strip, .mods, .about, .actions, .more, .achievements: return [[], ["Select", "View", "Show", "Open"]]
        case .store: return [[], ["Sort", "View"]]
        case .topGames: return []
        }
    }

    private func contextHints(_ model: Snapshot, _ state: SpotlightState) -> [HintItem] {
        if state.isLifted {
            return [HintItem(nil, L10n.text("◂ ▸  Move")), HintItem(.a, L10n.text("Drop")), HintItem(.b, L10n.text("Cancel"))]
        }
        if cardMenu != nil {
            return [HintItem(.a, L10n.text("Select")), HintItem(.b, L10n.text("Back"))]
        }
        switch state.focus {
        case .pills:
            return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("Select"))]
        case .strip:
            return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("View"))]
        case .about:
            // A opens Read more when there is one, otherwise it translates; X always translates.
            let text = currentPage?.presentation.description ?? ""
            let translate = DescriptionTranslateLine.buttonTitle(translator.phase(for: text))
            let select = aboutReadMore ? [HintItem(.a, L10n.text("Select"))]
                : translate.map { [HintItem(.a, $0) { translator.toggle(text) }] } ?? []
            let x = aboutReadMore ? translate.map { [HintItem(.x, $0) { translator.toggle(text) }] } ?? [] : []
            return [HintItem(.b, L10n.text("Back"))] + x + select
        case .mods, .actions:
            return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("Select"))]
        case .more:
            return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("Show"))]
        case .achievements:
            return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("Open"))]
        case .topGames:
            return [HintItem(.a, L10n.text("Show"))]
        case .store:
            // On the sort bar A sorts, and only when the focused order is not the one shown already.
            guard storeHost.focus.kind == .sort else { return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("View"))] }
            let chosen = ModStoreSort.allCases.firstIndex(of: storeHost.sort) == storeHost.focus.index
            return chosen ? [HintItem(.b, L10n.text("Back"))] : [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("Sort"))]
        case .row:
            switch model.selectedItem {
            case .card(let card):
                let more = [HintItem(.y, L10n.text("Card options"))]
                return card == .activity ? more : more + [HintItem(.a, card == .surprise ? L10n.text("Pick") : card == .mods ? L10n.text("Browse") : L10n.text("Open"))]
            case .game:
                if let steam = model.selectedCatalogGame, steam.integration == .steam {
                    return [HintItem(.y, L10n.text("Options"))] + SteamPlayCoordinator.shared.hint(for: steam)
                }
                guard let game = model.selectedGame else { return [] }
                if viewModel.portingPills(game) == .porting {
                    return [HintItem(.y, L10n.text("Options")), HintItem(.a, L10n.text("Porting"))]
                }
                if viewModel.portingPills(game).unavailableReason != nil, !runningGames.isRunning(game) {
                    return [HintItem(.y, L10n.text("Options"))]
                }
                if game.isPlayableLocally {
                    return [HintItem(.y, L10n.text("Options")), HintItem(.a, L10n.text("Play"))]
                }
                return [HintItem(.y, L10n.text("Options")), HintItem(.a, L10n.text("Build"))]
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
        hadGames = !viewModel.visibleCatalogGames.isEmpty
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
        let hasGames = !viewModel.visibleCatalogGames.isEmpty
        // The library loads after the first frame: a card picked while it was
        // empty gives way to the restored (or first) game.
        if !hadGames, hasGames, case .card = selectedItem {
            mutate { $0.selectedKey = nil }
        }
        hadGames = hasGames
        reconcile()
        if selectedItem == .card(.mods) { openStore() }
    }

    func reconcile() {
        // The lifted tile vanished (library reload, settings change): put it back.
        if let lifted = viewModel.spotlight.lift?.key, !items.contains(where: { $0.key == lifted }) {
            mutate { $0.cancelLift() }
        }
        let preferred = settings.settings.restoreLastGame ? settings.lastSelectedGameID : nil
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
        if selectedItem == .card(.mods) { openStore() } else { storeHost.close() }
        updateModsBackdrop()
        // A Steam game is a game too: moving to or from it keeps the art until the next arrives, never the wallpaper.
        artRule.select(viewModel.spotlight.selectedKey, isGame: selectedGame != nil || selectedCatalogGame?.integration == .steam)
        reloadMods()
        startModsOnline(viewModel.spotlight.focus)
        let game = selectedGame
        if let id = game?.id ?? selectedCatalogGame?.id { settings.rememberLastSelectedGame(id) }
        loadAchievements()
        if let game { viewModel.loadStoreMetadata(for: game) }
    }

    // MARK: - Mods

    /// The Mods band lives on the game page. Browsing the row releases the previous band without reading the next.
    func reloadMods() {
        guard viewModel.spotlight.focus != .row, let game = selectedGame else {
            modsHost.clearGame()
            return
        }
        modsHost.reload(game, viewModel: viewModel)
    }

    /// GameBanana is asked once the game's page is open, not while the row is browsed.
    func startModsOnline(_ focus: SpotlightFocusArea) {
        guard focus != .row, focus != .topGames, let game = selectedGame else { return }
        modsHost.startOnline(game, viewModel: viewModel)
    }

    /// Game options, opened on its Mods panel.
    func openMods() {
        guard let game = selectedGame else { return }
        SoundEffectService.shared.play(.click)
        viewModel.openGameOptions(game, from: .spotlight, opensMods: true)
    }

    // MARK: - Store

    /// The store asks about every visible game, last played first.
    func openStore() {
        storeHost.open(storeGames, viewModel: viewModel)
    }

    /// Every visible game, last played first: the store's games, and the card's cover.
    var storeGames: [PortedGame] {
        LibraryQuery(filter: .all).apply(to: viewModel.libraryGames, history: playSessions).filter { !$0.isHidden }
    }

    /// Between the card's text and the store's sort bar.
    static let storeGap: CGFloat = 56

    /// Section to section inside the store: quick, with a long soft landing.
    static let storeGlide = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.55)

    /// The store's scroll: the sort bar rides the first shift (the card's title rises to the top); every other
    /// section rises to the top line at 150, until the store's end sits above the hints.
    func storeOffset() -> CGFloat {
        let first = -canvas.u(Self.pageTravel)
        let kinds = storeHost.sections.map(\.kind)
        let at = storeHost.focus.position(in: storeHost.focusSections)
        guard at > 0 else { return first }
        let storeTop = canvas.u(420) + (blocks[.head] ?? 0) + canvas.u(Self.storeGap)
        let target = canvas.u(150) - storeTop - canvas.u(ModStoreLayout.top(of: at, in: kinds))
        let bottom = storeTop + canvas.u(ModStoreLayout.top(of: kinds.count, in: kinds)) + canvas.u(90)
        let end = canvas.size.height - canvas.u(Self.pageBottomInset) - bottom
        return min(first, max(target, end))
    }

    // MARK: - Art

    private func loadHero(_ game: PortedGame?) async {
        await art.loadHero(game: game, current: { selectedGame?.id },
                           metadata: game.flatMap { viewModel.storeMetadata[$0.id] }, artwork: artwork, personalizations: viewModel.personalizations,
                           // The logo leads (0.3 s); the art turns after it.
                           settle: 420_000_000, keepsWithoutGame: true)
        // The game's art is in (or it has none): the gold gives way under it.
        if let game, !Task.isCancelled, selectedGame?.id == game.id { modsBackdrop = false }
    }

    /// The art behind the page: none on a card; on a game its own art, or the previous game's while the next
    /// loads when browsing from game to game (never another game's art right after a card). The rule answers for
    /// the selection this render sees, so the art never drops out for the render before `onChange` runs.
    private func shownArt(_ model: Snapshot) -> NSImage? {
        let id = model.selectedGame?.id ?? model.selectedCatalogGame.flatMap { $0.integration == .steam ? $0.id : nil }
        guard let id, let image = art.image else { return nil }
        return art.key.hasPrefix(id.uuidString)
            || artRule.keepsOtherArt(selection: viewModel.spotlight.selectedKey, isGame: true) ? image : nil
    }

    /// Gold on the Mods card; another card turns it off at once, a game once its art has arrived.
    private func updateModsBackdrop() {
        if selectedItem == .card(.mods) {
            modsBackdrop = true
        } else if let game = selectedGame {
            if art.key.hasPrefix(game.id.uuidString) { modsBackdrop = false }
        } else {
            modsBackdrop = false
        }
    }

    // MARK: - Page

    /// How far the page rises once the focus leaves the row: the logo goes from 420 to 96.
    static let pageTravel: CGFloat = 324

    /// The page's scroll for the focus, in points. The pills and the strip
    /// share the first shift (the strip only moves further if it would sit
    /// under the hints); Details brings About this game and the column
    /// beside it up to 150 by their titles; More like this rises until the
    /// page's end sits above the hints, never further (`SpotlightPageScroll`).
    /// Positions add up the blocks' heights from the column's top at 420.
    func pageOffset(_ state: SpotlightState) -> CGFloat {
        offset(for: state.focus)
    }

    func offset(for area: SpotlightFocusArea) -> CGFloat {
        let first = -canvas.u(Self.pageTravel)
        let h = { (block: SpotlightPageBlock) in blocks[block] ?? 0 }
        let stripBottom = canvas.u(420) + h(.head) + h(.genres) + h(.strip)
        // The description block includes its 44 top padding.
        let aboutTop = stripBottom + canvas.u(44)
        // The Mods band (its top gap included) sits between About this game and More like this.
        let modsTop = stripBottom + h(.description) + canvas.u(Self.moreGap)
        let moreTop = stripBottom + h(.description) + h(.mods) + canvas.u(Self.moreGap)
        switch area {
        case .row, .topGames:
            return 0
        case .store:
            return storeOffset()
        case .pills:
            return first
        case .strip:
            // Keep the strip clear of the hints on the window's bottom edge.
            return min(first, canvas.size.height - canvas.u(Self.pageBottomInset) - stripBottom)
        case .about, .actions, .mods, .more, .achievements:
            // The bands report a height only when they are shown.
            let more = h(.more) > 0
            let pageBottom = stripBottom + h(.description) + h(.mods) + (more ? h(.more) : 0)
            let rest = SpotlightPageScroll.resting(
                first: first, aboutTop: aboutTop, moreTop: more ? moreTop : nil, pageBottom: pageBottom,
                top: canvas.u(150), viewport: canvas.size.height, bottomInset: canvas.u(Self.pageBottomInset))
            switch area {
            case .actions, .achievements: return rest.actions
            case .more: return rest.more
            case .mods:
                // The band's title rises to the top line, as More like this does, unless the page ends first.
                guard h(.mods) > 0 else { return rest.actions }
                return SpotlightPageScroll.resting(
                    first: first, aboutTop: aboutTop, moreTop: modsTop,
                    pageBottom: pageBottom, top: canvas.u(150), viewport: canvas.size.height,
                    bottomInset: canvas.u(Self.pageBottomInset)).more
            default:
                // Read more (or Show less, under the whole text) comes into view.
                return SpotlightPageScroll.revealing(rest.actions, bottom: aboutTop + h(.about),
                                                     viewport: canvas.size.height, bottomInset: canvas.u(Self.pageBottomInset))
            }
        }
    }

    /// The page's edges, in canvas units: clear up to `clear` from the window's
    /// edge, solid from `solid` (the top bar's breathing room, top and bottom).
    static let pageEdge = (top: (clear: CGFloat(28), solid: CGFloat(84)),
                           bottom: (clear: SeleneBottomScrim.contentClearance,
                                    solid: SeleneBottomScrim.contentClearance + 64))
    /// A focused band clears both the footer and its fade, with space for its ring.
    static let pageBottomInset: CGFloat = pageEdge.bottom.solid + 30

    private var pageMask: some View {
        let height = max(canvas.size.height, 1)
        let at = { (units: CGFloat) in min(max(canvas.u(units) / height, 0), 1) }
        let e = Self.pageEdge
        return LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: at(e.top.clear)),
            .init(color: .black, location: at(e.top.solid)),
            .init(color: .black, location: 1 - at(e.bottom.solid)),
            .init(color: .clear, location: 1 - at(e.bottom.clear)),
            .init(color: .clear, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    /// Between About this game (or the column beside it, whichever ends lower) and More like this.
    static let moreGap: CGFloat = 72

    /// About this game's cut for the page, as tall as the column beside it.
    func aboutExcerpt(_ page: SpotlightPageModel) -> DescriptionExcerpt {
        SpotlightDescription.excerpt(translator.displayed(page.presentation.description),
                                     columnHeight: blocks[.column] ?? 0, canvas: canvas)
    }

    /// The page's glide: one slow, soft curve (1 s, long ease out) for the whole screen.
    static let glide = Animation.timingCurve(0.4, 0, 0.1, 1, duration: 1.0)

    /// Moves the page to the focus, after the focus change has rendered, in
    /// transactions of its own. Leaving the row, the icons and the bar fade out
    /// first and the sections below fade in behind the glide; coming back, the
    /// sections go first and the icons return as the page settles. Under reduce
    /// motion the page jumps and only the fades run.
    func syncPage(glide: Animation = Self.glide) {
        let state = viewModel.spotlight
        let target = pageOffset(state)
        let onRow = state.focus == .row || state.focus == .topGames
        if holdScroll {
            // The focus followed a wheel scroll: the page stays where the user left it.
            holdScroll = false
        } else if reduceMotion {
            scroll = target
        } else if abs(scroll - target) > 0.5 {
            glideEnds = Date().addingTimeInterval(glide == Self.glide ? 1.05 : 0.6)
            withAnimation(glide) { scroll = target }
        }
        // Mods found in the background wait until the page rests: no rebuild under a glide.
        if selectedItem == .card(.mods) { storeHost.hold(until: glideEnds) }
        setPageFades(onRow: onRow, deep: isDeep(state))
    }

    /// Leaving the row, the icons and the bar fade out first and the sections
    /// below fade in behind; coming back, the sections go first.
    func setPageFades(onRow: Bool, deep: Bool) {
        if onRow == stripFull {
            withAnimation(.easeInOut(duration: onRow ? 0.7 : 0.9)) { stripFull = !onRow }
        }
        if onRow == !rowShown {
            if onRow {
                withAnimation(.easeInOut(duration: 0.45)) { belowShown = false }
                withAnimation(.easeInOut(duration: 0.7).delay(0.3)) { rowShown = true }
            } else {
                withAnimation(.easeInOut(duration: 0.55)) { rowShown = false }
                withAnimation(.easeInOut(duration: 0.8).delay(0.25)) { belowShown = true }
            }
        }
        if deep != dimmed {
            withAnimation(.easeInOut(duration: 0.8)) { dimmed = deep }
        }
    }

    /// Measured heights that differ by under a point are the same layout.
    static func sameLayout(_ a: [SpotlightPageBlock: CGFloat], _ b: [SpotlightPageBlock: CGFloat]) -> Bool {
        guard a.keys == b.keys else { return false }
        return a.allSatisfy { key, height in abs(height - (b[key] ?? .infinity)) < 1 }
    }

    /// Past the screenshots the art dims behind the text.
    func isDeep(_ state: SpotlightState) -> Bool {
        state.focus == .about || state.focus == .actions || state.focus == .mods || state.focus == .more
            || state.focus == .store || state.focus == .achievements
    }

    var currentPage: SpotlightPageModel? {
        if let game = selectedGame { return page(for: game) }
        return selectedCatalogGame.flatMap { $0.integration == .steam ? steamPage(for: $0) : nil }
    }

    private struct SteamRelatedRequest: Equatable {
        let appIDs: Set<UInt32>
        let language: String
    }

    private func loadCachedSteamRelated(_ request: SteamRelatedRequest) async {
        guard cachedSteamRelated?.request != request else { return }
        let traits = await SteamMetadataService.shared.cachedRelatedTraits(appIDs: request.appIDs, language: request.language)
        guard !Task.isCancelled else { return }
        cachedSteamRelated = (request, traits)
    }

    private func relatedTraits(for game: CatalogGame, language: String) -> MoreLikeThis.Traits? {
        if let native = game.nxnativeGame {
            return viewModel.storeMetadata[native.id].map {
                MoreLikeThis.Traits(developers: $0.developers, publishers: $0.publishers, genres: GameGenre.list($0.genres))
            }
        }
        guard let appID = game.steamGame?.appID else { return nil }
        let key = game.personalizationReference.key
        let loaded = steamFacts.metadata(for: game).flatMap { $0.language == language ? MoreLikeThis.Traits(steam: $0) : nil }
        let cached = cachedSteamRelated.flatMap { $0.request.language == language ? $0.traits[appID] : nil }
        let traits = loaded ?? cached
        let developer = steamFields.value(titleID: key, field: .developer)
        let publisher = steamFields.value(titleID: key, field: .publisher)
        let genres = steamFields.value(titleID: key, field: .genres)
        guard traits != nil || developer != nil || publisher != nil || genres != nil else { return nil }
        return MoreLikeThis.Traits(developers: developer.map { [$0] } ?? traits?.developers ?? [],
                                   publishers: publisher.map { [$0] } ?? traits?.publishers ?? [],
                                   genres: GameGenre.list(genres.map { $0.split(separator: ",").map(String.init) } ?? traits?.genres ?? []))
    }

    func steamPage(for game: CatalogGame) -> SpotlightPageModel {
        let visible = viewModel.visibleCatalogGames
        let playtimes = Dictionary(visible.map { ($0.id, playSessions.totalDuration(for: $0.id)) },
                                   uniquingKeysWith: { first, _ in first })
        let key = game.personalizationReference.key
        var overrides: [MetadataField: String] = [:]
        for field in MetadataField.allCases { overrides[field] = steamFields.value(titleID: key, field: field) }
        let presentation = GameDetailPresentation(
            steamRecord: game, metadata: steamFacts.metadata(for: game), overrides: overrides,
            totalPlaytime: playSessions.totalDuration(for: game.id),
            lastPlayed: playSessions.lastPlayed(for: game.id),
            sessions: playSessions.sessions, libraryGames: visible, playtimeByGame: playtimes)
        let facts = DetailsFacts.steamGame(game, metadata: steamFacts.metadata(for: game), overrides: overrides,
                                           volumeName: DetailsLink.volumeName(of: game))
        let app = presentation.appPath.isEmpty ? nil : URL(fileURLWithPath: presentation.appPath)
        let language = SteamMetadata.language(localization.language)
        let ids = belowShown ? MoreLikeThis.pick(for: game, in: visible, fallbackToOtherSources: true,
                                                traits: { relatedTraits(for: $0, language: language) }) : []
        let byID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return SpotlightPageModel(presentation: presentation, facts: facts,
                                  links: DetailsLink.links(app: app, store: presentation.storeURL,
                                                           hltb: presentation.hltbURL, viewModel: viewModel),
                                  more: ids.compactMap { byID[$0] }, buildBlocked: false)
    }

    func page(for game: PortedGame) -> SpotlightPageModel {
        let library = viewModel.libraryGames
        let playtimes = Dictionary(library.map { ($0.id, playSessions.totalDuration(for: $0.id)) },
                                   uniquingKeysWith: { first, _ in first })
        let presentation = GameDetailPresentation(
            game: game, metadata: viewModel.storeMetadata[game.id],
            totalPlaytime: playSessions.totalDuration(for: game.id),
            lastPlayed: playSessions.lastPlayed(for: game.id),
            sessions: playSessions.sessions, libraryGames: library, playtimeByGame: playtimes)
        let blocked = viewModel.compatibilityReport != nil && !viewModel.canPassToolchainGate
        let facts = DetailsFacts.switchGame(game, metadata: viewModel.storeMetadata[game.id],
                                            folderName: DetailsLink.folderName(of: game.url))
        let links = DetailsLink.links(app: game.url, store: presentation.storeURL, hltb: presentation.hltbURL,
                                      viewModel: viewModel)
        let ids = MoreLikeThis.pick(for: game, in: library,
                                    metadata: { viewModel.storeMetadata[$0] }, limit: 6)
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return SpotlightPageModel(presentation: presentation, facts: facts, links: links,
                                  more: ids.compactMap { byID[$0].map(CatalogGame.init(nxnative:)) }, buildBlocked: blocked)
    }

    /// About this game with the column beside it (a Steam game's achievements, then the source's panel):
    /// the same geometry, focus blocks and excerpt for every source.
    private func aboutAndColumn<Panel: View>(_ page: SpotlightPageModel, state: SpotlightState,
                                             @ViewBuilder panel: () -> Panel) -> some View {
        HStack(alignment: .top, spacing: 0) {
            let excerpt = aboutExcerpt(page)
            SpotlightDescription(text: translator.displayed(page.presentation.description),
                                 original: page.presentation.description,
                                 languageNote: page.presentation.descriptionLanguageNote, excerpt: excerpt,
                                 expanded: aboutExpanded, focused: state.focus == .about,
                                 onToggle: { aboutExpanded.toggle() })
                .spotlightBlock(.about)
                .preference(key: SpotlightReadMoreKey.self, value: excerpt.truncated)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: canvas.u(40)) {
                if let summary = selectedAchievements, let appID = selectedCatalogGame?.steamGame?.appID {
                    DetailsAchievementsCard(summary: summary, appID: appID, focused: state.focus == .achievements,
                                            onOpen: {
                                                guard !state.isLifted else { return }
                                                mutate { $0.focus = .achievements }
                                                openAchievements()
                                            })
                }
                panel()
            }
            .spotlightBlock(.column)
        }
        .frame(width: canvas.u(1700), alignment: .topLeading)
        .padding(.top, canvas.u(44))
        .spotlightBlock(.description)
    }

    /// The selected Steam game's achievements, when it has some and Steam's files read.
    var selectedAchievements: AchievementSummary? {
        guard let appID = selectedCatalogGame?.steamGame?.appID,
              let summary = achievementsStore.summaries[appID], summary.total > 0 else { return nil }
        return summary
    }

    /// The Details panel in the column beside About this game, the same for every source.
    private func detailsPanel(_ page: SpotlightPageModel, state: SpotlightState) -> some View {
        DetailsPanel(
            facts: page.facts, links: page.links,
            focusedLink: state.focus == .actions ? state.actionIndex : nil,
            onHoverLink: { index in
                guard state.focus == .actions, !isGliding else { return }
                mutate { $0.actionIndex = index }
            },
            onPressLink: { index in
                mutate { $0.focus = .actions; $0.actionIndex = index }
                if index < page.links.count { page.links[index].action() }
            },
            ratingQuery: selectedRatingQuery)
    }

    private var selectedRatingQuery: CriticRatingQuery? {
        if let game = selectedGame {
            return CriticRatingQuery(game: game, name: viewModel.storeMetadata[game.id]?.name)
        }
        guard let game = selectedCatalogGame, let steam = game.steamGame else { return nil }
        return CriticRatingQuery(name: steam.name, platform: .mac, steamAppID: steam.appID)
    }

    /// A Steam game's page under the head: About, its achievements, Details, then related games.
    private func steamPageBelow(_ page: SpotlightPageModel, state: SpotlightState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            aboutAndColumn(page, state: state) { detailsPanel(page, state: state) }
            relatedBand(page, state: state)
        }
    }

    /// The screenshot strip under the head, for any source: the same tiles, fade and arrival.
    private func screenshotStrip(id: UUID, titleID: String, urls: [URL], known: Bool, state: SpotlightState) -> some View {
        SpotlightScreenshotStrip(
            titleID: titleID,
            urls: urls,
            known: known,
            focusedIndex: state.focus == .strip ? state.stripIndex : nil,
            scrollIndex: state.stripIndex,
            artwork: artwork,
            onSelect: { index in
                guard !state.isLifted else { return }
                mutate { $0.focus = .strip; $0.stripIndex = index }
                openViewer(at: index)
            }
        )
        // On the row the screenshots dissolve downwards (Selene's home): the
        // hints sit on the dark below them, and the fade says there is more below.
        // Gradient stops do not animate, so the fade lifts by a solid layer
        // fading in over it, along with the glide. The mask reaches past the
        // strip's edges so the focus ring outside a tile shows.
        .mask(ZStack {
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.3),
                .init(color: .black.opacity(0.35), location: 0.62),
                .init(color: .black.opacity(0), location: 0.86)
            ], startPoint: .top, endPoint: .bottom)
            Color.black.opacity(stripFull ? 1 : 0)
        }
        .padding(-canvas.u(16)))
        // They arrive after the logo, not before it.
        .seleneReveal(delay: 0.6)
        .id(id)
        .padding(.top, canvas.u(30))
        .spotlightBlock(.strip)
    }

    /// Below the screenshots: About this game, with Details in a column on its right
    /// (beside it however long it is), then More like this.
    private func pageBelow(_ game: PortedGame, page: SpotlightPageModel, state: SpotlightState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            aboutAndColumn(page, state: state) {
                detailsPanel(page, state: state)
            }

            if let mods = modsHost.localMods, modsHost.game?.id == game.id {
                DetailsModsBand(
                    mods: mods,
                    records: modsHost.records,
                    gameBanana: modsHost.gameBanana,
                    focusedIndex: state.focus == .mods ? state.modsIndex : nil,
                    onFocus: { index in
                        guard !isGliding else { return }
                        mutate { $0.focus = .mods; $0.modsIndex = index }
                    },
                    onOpen: { index in
                        mutate { $0.focus = .mods; $0.modsIndex = index }
                        modsHost.activate(index, viewModel: viewModel, openMods: openMods)
                    })
                    .padding(.top, canvas.u(Self.moreGap))
                    .spotlightBlock(.mods)
            }

            relatedBand(page, state: state)
        }
    }

    @ViewBuilder
    private func relatedBand(_ page: SpotlightPageModel, state: SpotlightState) -> some View {
        if !page.more.isEmpty {
            DetailsMoreBand(
                games: page.more,
                focusedIndex: state.focus == .more ? state.moreIndex : nil,
                artwork: artwork,
                boxArt: viewModel.boxArt,
                boxArtIndexVersion: viewModel.boxArtIndexVersion,
                officialName: { viewModel.storeMetadata[$0.id]?.name },
                onFocus: { index in mutate { $0.focus = .more; $0.moreIndex = index } },
                onOpen: { index in
                    SoundEffectService.shared.play(.click)
                    selectGame(page.more[index].id)
                })
                .padding(.top, canvas.u(Self.moreGap))
                .spotlightBlock(.more)
        }
    }

    private func loadLogo(_ game: PortedGame?) async {
        await art.loadLogo(game: game, metadata: game.flatMap { viewModel.storeMetadata[$0.id]},
                           artwork: artwork, personalizations: viewModel.personalizations)
    }
}
