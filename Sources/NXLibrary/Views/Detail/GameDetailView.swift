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
/// are Screenshots (720), Build & Sources with Your activity (950) and More
/// like this (1180). A band below the one in focus peeks in, blurred, until
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
    @State var focus = DetailsFocus()
    /// The open screenshot viewer (the game's titleID, its urls and the paging state).
    @State var viewer: ViewerContext?
    /// "Read more" is open: the description scrolls, and the wheel scrolls it rather than the bands.
    @State var expanded = false
    @State var keyMonitor: Any?
    @State var wheel = DetailsWheel()
    @State var cache = DetailsModelCache()

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
                     bands: DetailsFocus.Bands(screenshots: urls.count, actions: rows.count, more: more.count),
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
        if viewModel.storeMetadataLoading.contains(game.id) { return false }
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
        .animation(.easeOut(duration: 0.2), value: viewer != nil)
        .frame(width: canvas.size.width, height: canvas.size.height, alignment: .topLeading)
        .clipped()
        .onAppear(perform: appear)
        .onDisappear {
            removeKeyMonitor()
            router.isScreenshotViewerOpen = false
        }
        .onChange(of: viewer != nil) { router.isScreenshotViewerOpen = $0 }
        .onChange(of: model.bands) { _ in settleFocus(model.bands) }
        // The key monitor captures this view's value: reinstall it when the game changes.
        .onChange(of: game) { _ in
            removeKeyMonitor()
            installKeyMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxDetailGamepadAction)) { note in
            guard viewModel.alertMessage == nil else { return }
            if let action = note.object as? GamepadAction { handle(action) }
        }
        .task(id: art.heroTaskKey(game, metadata: metadata, apiKey: settings.settings.steamGridDbApiKey)) {
            await art.loadHero(game: game, current: { game.id }, metadata: metadata, artwork: artwork,
                               steamGridDB: viewModel.steamGridDB,
                               apiKey: settings.settings.steamGridDbApiKey)
        }
        .task(id: art.logoTaskKey(game, metadata: metadata, apiKey: settings.settings.steamGridDbApiKey)) {
            await art.loadLogo(game: game, metadata: metadata, artwork: artwork,
                               steamGridDB: viewModel.steamGridDB,
                               apiKey: settings.settings.steamGridDbApiKey)
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
        }
    }

    /// Selene's band pitch (230), and 100 more for the tall last band so its covers clear the hints.
    var pageShift: CGFloat {
        switch focus.zone {
        case DetailsFocus.actionsZone: return -230
        case DetailsFocus.moreZone: return -560
        default: return 0
        }
    }

    private func page(_ model: Model) -> some View {
        ZStack(alignment: .topLeading) {
            DetailsTopBlock(game: game, logo: art.logo(for: game),
                            presentation: model.presentation,
                            isRunning: runningGames.isRunning(game),
                            focusedPill: focus.zone == DetailsFocus.topZone ? focus.pill : nil,
                            primaryEnabled: model.primaryEnabled,
                            expanded: $expanded,
                            onPrimary: { pressPill(0) },
                            onSecondary: { pressPill(1) },
                            onFavorite: { pressPill(2) },
                            onHoverPill: { hoverPill($0) })
                .offset(x: canvas.u(110), y: canvas.u(96))

            band(zone: DetailsFocus.screenshotsZone) {
                DetailsScreenshotsBand(
                    titleID: game.titleId ?? game.uniqueKey,
                    urls: model.screenshots,
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

            band(zone: DetailsFocus.actionsZone) {
                HStack(alignment: .top, spacing: 0) {
                    BuildSourcesPanel(
                        presentation: model.presentation,
                        appFileName: game.url.lastPathComponent,
                        buildBlocked: model.buildBlocked && model.presentation.canRebuild,
                        rows: model.rows,
                        focusedRow: focus.zone == DetailsFocus.actionsZone ? focus.action : nil,
                        onHoverRow: { hoverRow($0) },
                        onPressRow: { pressRow($0) })
                    Spacer(minLength: 0)
                    DetailsActivityColumn(presentation: model.presentation)
                }
                .frame(width: canvas.u(1700), alignment: .topLeading)
            }
            .offset(x: canvas.u(110), y: canvas.u(970))

            if !model.more.isEmpty {
                band(zone: DetailsFocus.moreZone) {
                    DetailsMoreBand(
                        games: model.more,
                        focusedIndex: focus.zone == DetailsFocus.moreZone ? focus.more : nil,
                        steamGridDbApiKey: settings.settings.steamGridDbApiKey,
                        artwork: artwork,
                        steamGridDB: viewModel.steamGridDB,
                        coverURL: { viewModel.storeMetadata[$0.id]?.imageURL },
                        onFocus: { focusPointer(zone: DetailsFocus.moreZone, index: $0, bands: model.bands) },
                        onOpen: { index in
                            focusPointer(zone: DetailsFocus.moreZone, index: index, bands: model.bands)
                            selectOnSpotlight(model.more[index])
                        })
                }
                .offset(x: canvas.u(110), y: canvas.u(1200))
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

    // MARK: - Lifecycle

    private func appear() {
        installKeyMonitor()
        router.isSearchPresented = false
        viewModel.loadStoreMetadata(for: game)
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
