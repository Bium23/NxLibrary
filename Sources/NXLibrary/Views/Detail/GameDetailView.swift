import SwiftUI
import AppKit
import NXLibraryCore

/// The latest render's model. The key monitor and the input handlers run
/// outside `body`, so they read it from here instead of recomputing it per key.
final class DetailsModelCache {
    var model: GameDetailView.Model?
}

/// The Details page (spec §5.4, Selene GameDetails + DetailsStage). The top
/// block sits on the stage; Down glides the page up into the bands, which
/// are Screenshots (720), Mods (950, for a game with a title ID), Build &
/// Sources with Your activity and More like this, one band pitch (230) apart. A band below the one in focus peeks in, blurred, until
/// it is focused. Input lives in GameDetailView+Input.swift.
struct GameDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var playSessions: PlaySessionStore
    @ObservedObject var runningGames: RunningGameMonitor
    @ObservedObject var artwork: ArtworkStore
    let game: PortedGame

    @Environment(\.seleneCanvas) var canvas
    @Environment(\.seleneReduceMotion) var reduceMotion

    @StateObject var art = SeleneHeroArt()
    /// Art the player picks redraws the hero and logo (their task keys carry its revision).
    @ObservedObject var picks = ArtworkPicks.shared
    @State var focus = DetailsFocus()
    /// The open screenshot viewer (the game's titleID, its urls and the paging state).
    @State var viewer: ViewerContext?
    /// "Read more" is open: the description scrolls, and the wheel scrolls it rather than the bands.
    @State var expanded = false
    @State var keyMonitor: Any?
    @State var wheel = DetailsWheel()
    @State var cache = DetailsModelCache()
    /// The game's mods, read when the page appears and when Game options or the app comes back; nil without a
    /// title ID (no Mods band).
    @State var localMods: [LocalMod]?
    /// GameBanana records of the installed mods, by GameBanana mod id.
    @State var modRecords: [Int: ModRecord] = [:]
    /// The GameBanana part of the Mods band (match, mods that work, installs).
    @StateObject var gameBanana = GameBananaBandModel()
    @StateObject var gameBananaFind = GameBananaFindModel()
    /// The open mod detail panel.
    @State var modDetail: AvailableMod?
    @State var modDetailFocus = 0
    @State var modDetailExpanded = false

    struct ViewerContext: Equatable {
        var titleID: String
        var urls: [URL]
        var state: ScreenshotViewerState
    }

    // MARK: - Model

    /// Everything one render needs, computed once per body.
    struct Model {
        let presentation: GameDetailPresentation
        let rows: [BuildSourcesRow]
        let screenshots: [URL]
        let screenshotsKnown: Bool
        let more: [PortedGame]
        let mods: [LocalMod]?
        let bands: DetailsFocus.Bands
        /// The Metal gate refuses new builds (a known report that does not pass, without the override).
        let buildBlocked: Bool
        /// Play, or Build when it can run; otherwise the pill looks dim.
        let primaryEnabled: Bool
    }

    /// The last render's model (falls back to a fresh one before the first render).
    var currentModel: Model { cache.model ?? model }

    var model: Model {
        let p = presentation
        let urls = Array((metadata?.screenshotURLs ?? []).prefix(SpotlightScreenshotStrip.maxCount))
        let more = moreGames
        let blocked = toolchainBlocked
        let rows = actionRows(p, buildBlocked: blocked)
        return Model(presentation: p, rows: rows, screenshots: urls,
                     screenshotsKnown: screenshotsKnown,
                     more: more,
                     mods: localMods,
                     bands: DetailsFocus.Bands(screenshots: urls.count, mods: localMods.map { DetailsModsBand.tiles(mods: $0, gameBanana: gameBanana).count } ?? 0,
                                               actions: rows.count, more: more.count),
                     buildBlocked: blocked,
                     primaryEnabled: p.canPlay || (p.canRebuild && !blocked))
    }

    var metadata: NintendoStoreMetadata? { viewModel.storeMetadata[game.id] }

    /// Blocked only once the compatibility report is known and does not pass;
    /// before it loads the build is not dimmed (the build path still explains a refusal).
    var toolchainBlocked: Bool {
        viewModel.compatibilityReport != nil && !viewModel.canPassToolchainGate
    }

    var presentation: GameDetailPresentation {
        let library = viewModel.libraryGames
        let playtimes = Dictionary(library.map { ($0.id, playSessions.totalDuration(for: $0.id)) },
                                   uniquingKeysWith: { first, _ in first })
        return GameDetailPresentation(
            game: game,
            metadata: metadata,
            totalPlaytime: playSessions.totalDuration(for: game.id),
            lastPlayed: playSessions.lastPlayed(for: game.id),
            sessions: playSessions.sessions,
            libraryGames: library,
            playtimeByGame: playtimes
        )
    }

    /// Other games from the library, most alike first (`MoreLikeThis`); nothing without metadata.
    var moreGames: [PortedGame] {
        let ids = MoreLikeThis.pick(for: game, in: viewModel.libraryGames,
                                    metadata: { viewModel.storeMetadata[$0] }, limit: 6)
        let byID = Dictionary(viewModel.libraryGames.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    /// "No screenshots" only once the answer is final: not before the first request
    /// starts, nor while a stale empty cache entry is being refetched.
    var screenshotsKnown: Bool {
        if viewModel.storeMetadataLoading.contains(game.id) || viewModel.screenshotLookups.contains(game.id) { return false }
        guard let titleId = game.titleId, !titleId.isEmpty else { return true }
        return metadata != nil || viewModel.storeMetadataErrors[game.id] != nil
    }

    /// Build & Sources' actions, in grid order.
    func actionRows(_ p: GameDetailPresentation, buildBlocked: Bool) -> [BuildSourcesRow] {
        BuildSourcesRow.rows(for: game, presentation: p, buildBlocked: buildBlocked,
                             viewModel: viewModel, rebuild: { rebuild() })
    }

    // MARK: - Body

    var body: some View {
        let model = self.model
        cache.model = model
        return ZStack(alignment: .topLeading) {
            DetailsBackground(image: art.image, imageKey: art.key,
                              fallback: GameIconProvider.icon(for: game),
                              shade: settings.settings.backgroundShade)
            SeleneBottomScrim()
            stage(model)
                .frame(width: canvas.stageSize.width, height: canvas.stageSize.height, alignment: .topLeading)
                .clipped()
                .offset(x: canvas.stageOrigin.x, y: canvas.stageOrigin.y)
        }
        .overlay(viewerOverlay)
        .overlay(gameBananaOverlay)
        .animation(.easeOut(duration: 0.2), value: gameBananaFind.isOpen)
        .animation(.easeOut(duration: 0.2), value: modDetail?.id)
        .animation(.easeOut(duration: 0.2), value: viewer != nil)
        .frame(width: canvas.size.width, height: canvas.size.height, alignment: .topLeading)
        .clipped()
        .onAppear(perform: appear)
        .onAppear { focus.setPillLimit(viewModel.portingPills(game).count) }
        .onChange(of: viewModel.portingPills(game).count) { focus.setPillLimit($0) }
        .onDisappear {
            gameBanana.stop()
            gameBananaFind.close()
            modDetail = nil
            removeKeyMonitor()
            router.isScreenshotViewerOpen = false
        }
        .onChange(of: viewer != nil) { router.isScreenshotViewerOpen = $0 }
        .onChange(of: model.bands) { _ in settleFocus(model.bands) }
        // Game options (its Mods panel) closing, or NX Library coming back from Finder, re-reads the mods.
        .onChange(of: viewModel.gameForSettingsSheet == nil) { closed in if closed { reloadMods() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reloadMods() }
        // The key monitor captures this view's value: reinstall it when the game changes.
        .onChange(of: game) { _ in
            removeKeyMonitor()
            installKeyMonitor()
            gameBanana.stop()
            reloadMods()
            startGameBanana()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxDetailGamepadAction)) { note in
            guard viewModel.alertMessage == nil, viewModel.settingsNotice == nil else { return }
            if let action = note.object as? GamepadAction { handle(action) }
        }
        .task(id: art.heroTaskKey(game, metadata: metadata)) {
            await art.loadHero(game: game, current: { game.id }, metadata: metadata, artwork: artwork)
        }
        .task(id: art.logoTaskKey(game, metadata: metadata)) {
            await art.loadLogo(game: game, metadata: metadata, artwork: artwork)
        }
    }

    // MARK: - Stage

    private func stage(_ model: Model) -> some View {
        ZStack(alignment: .topLeading) {
            page(model)
                .offset(y: canvas.u(pageShift))
                // The glide is movement: reduce motion makes it instant.
                .animation(reduceMotion ? nil : SeleneTheme.cubicOut(0.32), value: focus.zone)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                SeleneHintsBar(left: [HintItem(.b, "Back", action: { router.back() })],
                               right: [HintItem(.y, "Options"), HintItem(.a, "Select")],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }
            .seleneOverlaidHints(router.overlayHasHints(viewModel))
        }
    }

    /// Selene's band pitch (230), and 100 more for the tall last band so its covers clear the hints. The Mods band,
    /// when there is one, pushes the bands below it one pitch down.
    var pageShift: CGFloat {
        let mods = modsBandShift
        switch focus.zone {
        case DetailsFocus.modsZone: return -230
        case DetailsFocus.actionsZone: return -230 - mods
        case DetailsFocus.moreZone: return -560 - mods
        default: return 0
        }
    }

    var modsBandShift: CGFloat { currentModel.mods == nil ? 0 : 230 }

    private func page(_ model: Model) -> some View {
        ZStack(alignment: .topLeading) {
            DetailsTopBlock(game: game, logo: art.logo(for: game),
                            presentation: model.presentation,
                            isRunning: runningGames.isRunning(game),
                            cheatsOn: viewModel.cheatsOn(for: game),
                            focusedPill: focus.zone == DetailsFocus.topZone ? focus.pill : nil,
                            primaryEnabled: model.primaryEnabled,
                            expanded: $expanded,
                            onPrimary: { pressPill(0) },
                            onSecondary: { pressPill(1) },
                            onFavorite: { pressPill(2) },
                            onHoverPill: { hoverPill($0) },
                            pillSet: viewModel.portingPills(game),
                            etaText: viewModel.portingETAText,
                            onPill: { pressPill($0) },
                            onOpenLog: { viewModel.revealLog(for: game) })
                .offset(x: canvas.u(110), y: canvas.u(96))

            band(zone: DetailsFocus.screenshotsZone) {
                DetailsScreenshotsBand(
                    titleID: game.titleId ?? game.uniqueKey,
                    urls: model.screenshots,
                    source: metadata?.screenshotSource,
                    known: model.screenshotsKnown,
                    focusedIndex: focus.zone == DetailsFocus.screenshotsZone ? focus.shot : nil,
                    artwork: artwork,
                    onFocus: { focusPointer(zone: DetailsFocus.screenshotsZone, index: $0, bands: model.bands) },
                    onOpen: { index in
                        focusPointer(zone: DetailsFocus.screenshotsZone, index: index, bands: model.bands)
                        openViewer(at: index)
                    })
            }
            .offset(x: canvas.u(110), y: canvas.u(740))

            if let mods = model.mods {
                band(zone: DetailsFocus.modsZone) {
                    DetailsModsBand(
                        mods: mods,
                        records: modRecords,
                        gameBanana: gameBanana,
                        focusedIndex: focus.zone == DetailsFocus.modsZone ? focus.mod : nil,
                        onFocus: { focusPointer(zone: DetailsFocus.modsZone, index: $0, bands: model.bands) },
                        onOpen: { index in
                            focusPointer(zone: DetailsFocus.modsZone, index: index, bands: model.bands)
                            activateModsTile(index)
                        })
                }
                .offset(x: canvas.u(110), y: canvas.u(970))
            }

            band(zone: DetailsFocus.actionsZone) {
                HStack(alignment: .top, spacing: 0) {
                    BuildSourcesPanel(
                        presentation: model.presentation,
                        appFileName: game.url.lastPathComponent,
                        buildBlocked: model.buildBlocked && model.presentation.canRebuild,
                        blockedHint: viewModel.toolchainGateSummary,
                        rows: model.rows,
                        focusedRow: focus.zone == DetailsFocus.actionsZone ? focus.action : nil,
                        onHoverRow: { hoverRow($0) },
                        onPressRow: { pressRow($0) })
                    Spacer(minLength: 0)
                    DetailsActivityColumn(presentation: model.presentation)
                }
                .frame(width: canvas.u(1700), alignment: .topLeading)
            }
            .offset(x: canvas.u(110), y: canvas.u(970 + (model.mods == nil ? 0 : 230)))

            if !model.more.isEmpty {
                band(zone: DetailsFocus.moreZone) {
                    DetailsMoreBand(
                        games: model.more,
                        focusedIndex: focus.zone == DetailsFocus.moreZone ? focus.more : nil,
                        artwork: artwork,
                        boxArt: viewModel.boxArt,
                        boxArtIndexVersion: viewModel.boxArtIndexVersion,
                        officialName: { viewModel.storeMetadata[$0.id]?.name },
                        onFocus: { focusPointer(zone: DetailsFocus.moreZone, index: $0, bands: model.bands) },
                        onOpen: { index in
                            focusPointer(zone: DetailsFocus.moreZone, index: index, bands: model.bands)
                            selectOnSpotlight(model.more[index])
                        })
                }
                .offset(x: canvas.u(110), y: canvas.u(1200 + (model.mods == nil ? 0 : 230)))
            }
        }
    }

    /// A band's look (Selene's DetailsStage.Blur): the band in focus, and the
    /// first band while the top block has focus, are sharp; every band below
    /// that one peeks, blurred and faded. Bands above keep full opacity.
    private func band<Content: View>(zone: Int, @ViewBuilder _ content: () -> Content) -> some View {
        let shown = max(focus.zone, DetailsFocus.screenshotsZone)
        let below = zone > shown
        return content()
            .blur(radius: below ? canvas.u(12) : 0)
            .opacity(below ? 0.55 : 1)
            .animation(SeleneTheme.cubicOut(0.32), value: shown)
    }

    // MARK: - Viewer

    @ViewBuilder
    private var viewerOverlay: some View {
        if let viewer {
            ScreenshotViewer(titleID: viewer.titleID, urls: viewer.urls, state: viewer.state,
                             artwork: artwork, onClose: closeViewer)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var gameBananaOverlay: some View {
        if let mod = modDetail {
            ModDetailPanel(model: gameBanana, mod: mod, game: game, installed: modRecords[mod.id],
                           focus: $modDetailFocus, expanded: $modDetailExpanded, onClose: closeModDetail)
                .transition(.opacity)
        } else if gameBananaFind.isOpen {
            GameBananaFindPanel(model: gameBananaFind, band: gameBanana, gameName: game.name)
                .transition(.opacity)
        }
    }

    // MARK: - Lifecycle

    private func appear() {
        installKeyMonitor()
        router.isSearchPresented = false
        viewModel.loadStoreMetadata(for: game)
        reloadMods()
        startGameBanana()
        focus = DetailsFocus()
        settleFocus(model.bands)
    }

    func settleFocus(_ bands: DetailsFocus.Bands) {
        var next = focus
        next.settle(in: bands)
        if next != focus { focus = next }
    }
}

/// Wheel steps for the bands: one step per 0.4 s of scrolling, so a flick moves a band, not three.
struct DetailsWheel: Equatable {
    private var accumulated: CGFloat = 0
    private var lastEvent: TimeInterval = 0
    private var lastStep: TimeInterval = 0

    /// Scroll down (content up) is Down. A gap of 0.25 s starts a new gesture.
    /// `threshold` is how far a gesture must travel: small for line-based mouse wheels, large for trackpads.
    mutating func feed(_ delta: CGFloat, at time: TimeInterval, threshold: CGFloat) -> GamepadAction? {
        if time - lastEvent > 0.25 { accumulated = 0 }
        lastEvent = time
        accumulated += delta
        guard abs(accumulated) >= threshold, time - lastStep >= 0.4 else { return nil }
        accumulated = 0
        lastStep = time
        return delta < 0 ? .navigateDown : .navigateUp
    }
}
