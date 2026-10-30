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
/// description with Your activity and Build & Sources beside it, More like this. Down
/// from the row shifts everything up (the row and the bar fade away, the logo
/// rises to the top) and keeps going section by section; Up comes back.
public struct SpotlightView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var playSessions: PlaySessionStore
    @ObservedObject var runningGames: RunningGameMonitor
    @ObservedObject var artwork: ArtworkStore

    @Environment(\.seleneCanvas) var canvas
    @Environment(\.seleneReduceMotion) var reduceMotion

    @StateObject var art = SeleneHeroArt()
    /// Art the player picks redraws the hero and logo (their task keys carry its revision).
    @ObservedObject var picks = ArtworkPicks.shared
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
        SeleneHomeChrome(
            leftHints: state.isLifted || cardMenu != nil || state.focus != .row
                ? [] : HintItem.homeGlobals(other: "Collection"),
            rightHints: contextHints(model, state),
            rightReserve: hintReserve(state),
            hintsHidden: router.overlayHasHints(viewModel),
            backdrop: {
                SeleneArtBackground(image: art.image, imageKey: art.key,
                                    shade: settings.settings.backgroundShade, crossfade: 0.8)
                // Deeper in the page the art dims so the text reads.
                Color.black.opacity(dimmed ? 0.4 : 0)
                    .allowsHitTesting(false)
            },
            stage: { stage(model, state: state) })
        .overlay(viewerOverlay)
        .animation(.easeOut(duration: 0.2), value: viewer != nil)
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
        .onChange(of: viewModel.spotlight.selectedKey) { _ in
            aboutExpanded = false
            selectionChanged()
        }
        .onChange(of: viewModel.spotlight.focus) { _ in syncPage() }
        .onChange(of: blocks) { _ in syncPage() }
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
        .task(id: art.heroTaskKey(model.selectedGame, metadata: model.selectedGame.flatMap { viewModel.storeMetadata[$0.id] })) { await loadHero(model.selectedGame) }
        .task(id: art.logoTaskKey(model.selectedGame, metadata: model.selectedGame.flatMap { viewModel.storeMetadata[$0.id] })) { await loadLogo(model.selectedGame) }
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
                .opacity(rowShown ? 1 : 0)
                .allowsHitTesting(rowShown)

            ZStack(alignment: .topLeading) {
                SpotlightRowView(
                    items: items,
                    gamesByID: model.gamesByID,
                    selectedKey: state.selectedKey,
                    liftedKey: state.lift?.key,
                    isEmptyFilter: items.contains { if case .game = $0 { return true } else { return false } }
                        ? nil : filter,
                    artwork: artwork,
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
                .opacity(rowShown ? 1 : 0)
                .allowsHitTesting(rowShown)

                SpotlightFilterPill(filter: pillFilter, count: games.count)
                    .offset(x: canvas.u(80), y: canvas.u(88))
                    // Opacity fades always run, reduce motion or not.
                    .opacity(pillVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: pillVisible)

                info(model, state: state)
                    .offset(x: canvas.u(80), y: canvas.u(420))
            }
            .onPreferenceChange(SpotlightBlockKey.self) { heights in
                if !Self.sameLayout(heights, blocks) { blocks = heights }
            }
            // One page: the focus scrolls it; the glide is movement, so reduce motion jumps.
            .offset(y: scroll)
            // The page fades out short of the window's edges, top and bottom.
            .frame(width: canvas.stageSize.width, height: canvas.size.height, alignment: .topLeading)
            .mask(pageMask)

            // Off the row, the page has risen: there is more above (More like this is the end).
            SpotlightUpHint()
                .frame(width: canvas.stageSize.width)
                .padding(.top, canvas.u(24))
                .opacity([.pills, .strip, .about, .actions].contains(state.focus) ? 1 : 0)
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
            let page = page(for: game)
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
                    }
                )
                .id(game.id)
                .spotlightBlock(.head)

                if !page.presentation.genres.isEmpty {
                    SpotlightGenreChips(genres: page.presentation.genres)
                        .padding(.top, canvas.u(20))
                        .spotlightBlock(.genres)
                }

                SpotlightScreenshotStrip(
                    titleID: game.titleId ?? game.uniqueKey,
                    urls: metadata?.screenshotURLs ?? [],
                    known: screenshotsKnown(game, metadata: metadata),
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
                .id(game.id)
                .padding(.top, canvas.u(30))
                .spotlightBlock(.strip)

                pageBelow(game, page: page, state: state)
                    // Hidden while the row has focus: it rises in with the page.
                    .opacity(belowShown ? 1 : 0)
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

    /// The A slot keeps one width per place (row, page), so the prompts hold still
    /// as the focus moves. Y and B sit leftmost, where a longer label shifts nothing.
    private func hintReserve(_ state: SpotlightState) -> [[String]] {
        if state.isLifted || cardMenu != nil { return [] }
        switch state.focus {
        case .row: return [[], ["Play", "Build", "Pick", "Open"]]
        case .pills, .strip, .about, .actions, .more: return [[], ["Select", "View", "Show"]]
        case .topGames: return []
        }
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
            return [HintItem(.b, "Back"), HintItem(.a, "Select")]
        case .strip:
            return [HintItem(.b, "Back"), HintItem(.a, "View")]
        case .about, .actions:
            return [HintItem(.b, "Back"), HintItem(.a, "Select")]
        case .more:
            return [HintItem(.b, "Back"), HintItem(.a, "Show")]
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
                    return [HintItem(.y, "Options"), HintItem(.a, "Play")]
                }
                return [HintItem(.y, "Options"), HintItem(.a, "Build")]
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
                           // The logo leads (0.3 s); the art turns after it.
                           settle: 420_000_000)
    }

    // MARK: - Page

    /// How far the page rises once the focus leaves the row: the logo goes from 420 to 96.
    static let pageTravel: CGFloat = 324

    /// The page's scroll for the focus, in points. The pills and the strip
    /// share the first shift (the strip only moves further if it would sit
    /// under the hints); Build & Sources brings About this game and the column
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
        let moreTop = stripBottom + h(.description) + canvas.u(Self.moreGap)
        switch area {
        case .row, .topGames:
            return 0
        case .pills:
            return first
        case .strip:
            // Keep the strip clear of the hints on the window's bottom edge.
            return min(first, canvas.size.height - canvas.u(130) - stripBottom)
        case .about, .actions, .more:
            // The band reports a height only when it has games.
            let more = h(.more) > 0
            let rest = SpotlightPageScroll.resting(
                first: first, aboutTop: aboutTop, moreTop: more ? moreTop : nil,
                pageBottom: stripBottom + h(.description) + (more ? h(.more) : 0),
                top: canvas.u(150), viewport: canvas.size.height, bottomInset: canvas.u(130))
            switch area {
            case .actions: return rest.actions
            case .more: return rest.more
            default:
                // Read more (or Show less, under the whole text) comes into view.
                return SpotlightPageScroll.revealing(rest.actions, bottom: aboutTop + h(.about),
                                                     viewport: canvas.size.height, bottomInset: canvas.u(130))
            }
        }
    }

    /// The page's edges, in canvas units: clear up to `clear` from the window's
    /// edge, solid from `solid` (the top bar's breathing room, top and bottom).
    static let pageEdge = (top: (clear: CGFloat(28), solid: CGFloat(84)),
                           bottom: (clear: CGFloat(36), solid: CGFloat(100)))

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
        SpotlightDescription.excerpt(page.presentation.description, columnHeight: blocks[.column] ?? 0, canvas: canvas)
    }

    /// The page's glide: one slow, soft curve (1 s, long ease out) for the whole screen.
    static let glide = Animation.timingCurve(0.4, 0, 0.1, 1, duration: 1.0)

    /// Moves the page to the focus, after the focus change has rendered, in
    /// transactions of its own. Leaving the row, the icons and the bar fade out
    /// first and the sections below fade in behind the glide; coming back, the
    /// sections go first and the icons return as the page settles. Under reduce
    /// motion the page jumps and only the fades run.
    func syncPage() {
        let state = viewModel.spotlight
        let target = pageOffset(state)
        let onRow = state.focus == .row || state.focus == .topGames
        if holdScroll {
            // The focus followed a wheel scroll: the page stays where the user left it.
            holdScroll = false
        } else if reduceMotion {
            scroll = target
        } else if abs(scroll - target) > 0.5 {
            glideEnds = Date().addingTimeInterval(1.05)
            withAnimation(Self.glide) { scroll = target }
        }
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
        state.focus == .about || state.focus == .actions || state.focus == .more
    }

    var currentPage: SpotlightPageModel? { selectedGame.map(page(for:)) }

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
        let rows = BuildSourcesRow.rows(for: game, presentation: presentation, buildBlocked: blocked,
                                        viewModel: viewModel, rebuild: { rebuild(game, canRebuild: presentation.canRebuild) })
        let ids = MoreLikeThis.pick(for: game, in: library,
                                    metadata: { viewModel.storeMetadata[$0] }, limit: 6)
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return SpotlightPageModel(presentation: presentation, rows: rows,
                                  more: ids.compactMap { byID[$0] }, buildBlocked: blocked)
    }

    private func rebuild(_ game: PortedGame, canRebuild: Bool) {
        guard canRebuild else {
            SoundEffectService.shared.play(.error)
            return
        }
        SoundEffectService.shared.play(.click)
        viewModel.startBuild(for: game)
        if viewModel.isBuilding { router.openAddGame() }
    }

    /// Below the screenshots: About this game, with Your activity and Build &
    /// Sources in a column on its right (beside it however long it is), then More like this.
    private func pageBelow(_ game: PortedGame, page: SpotlightPageModel, state: SpotlightState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                SpotlightDescription(text: page.presentation.description, excerpt: aboutExcerpt(page),
                                     expanded: aboutExpanded, focused: state.focus == .about,
                                     onToggle: { aboutExpanded.toggle() })
                    .spotlightBlock(.about)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: canvas.u(40)) {
                    DetailsActivityColumn(presentation: page.presentation)
                    BuildSourcesPanel(
                        presentation: page.presentation,
                        appFileName: game.url.lastPathComponent,
                        buildBlocked: page.buildBlocked && page.presentation.canRebuild,
                        rows: page.rows,
                        focusedRow: state.focus == .actions ? state.actionIndex : nil,
                        onHoverRow: { index in
                            guard state.focus == .actions, !isGliding else { return }
                            mutate { $0.actionIndex = index }
                        },
                        onPressRow: { index in
                            mutate { $0.focus = .actions; $0.actionIndex = index }
                            if index < page.rows.count { page.rows[index].action() }
                        },
                        width: BuildSourcesPanel.narrowWidth)
                }
                .spotlightBlock(.column)
            }
            .frame(width: canvas.u(1700), alignment: .topLeading)
            .padding(.top, canvas.u(44))
            .spotlightBlock(.description)

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
    }

    private func loadLogo(_ game: PortedGame?) async {
        await art.loadLogo(game: game, metadata: game.flatMap { viewModel.storeMetadata[$0.id]},
                           artwork: artwork)
    }
}
