import SwiftUI
import AppKit
import NXLibraryCore

/// Spotlight's entrance, the app's opening: the first time the home shows after launch (`SpotlightEntrance`,
/// Selene's flight at a calmer pace). While the welcome or Setup covers the screen, the row, the bar, the pill,
/// the info and the art stay hidden over a shared moving moonlight. Once the cover has gone, the entrance waits for the
/// breath on the moving moonlight and for the visible tiles' art (at most 1 s more), then the background fades in
/// slowly, the tiles fly in from the centre while they grow and the info rises. The first key, click, wheel or controller press lands everything at once, then acts. Every
/// later visit, Reduce motion and a launch on another screen land it at once.
extension SpotlightView {
    /// Drawn over Spotlight: the welcome until its fade has ended, or Setup (the first launch's pages come first).
    var isOverlaid: Bool { viewModel.isWelcomeOpen || viewModel.showSetupCheck }

    /// Overlaid, or the window still taking its launch mode (a fullscreen transition would cut the flight).
    var isCovered: Bool { isOverlaid || viewModel.isWindowSettling }

    /// What a held or not-yet-arrived piece shows: nothing to the eye (under half a step of 8 bits), but drawn. *Why:*
    /// at opacity 0 a tile was first drawn the moment it appeared, its shadow, shine and app icon in one frame
    /// (measured: SwiftUI's late frames fell exactly as tiles 5, 7 and 11 began). Drawn under the cover, the flight
    /// only moves what is ready, as Selene flies a cached picture of each tile.
    static let unseenOpacity = 0.001

    /// The row while held: drawn, not seen (`unseenOpacity`); 0 off the row as before.
    var rowOpacity: Double {
        guard rowShown else { return 0 }
        return entrance.holdsHidden ? Self.unseenOpacity : 1
    }

    /// The pieces' clocks run (`View.entrance`): from the start of the flight on.
    var entranceLaunched: Bool { entrance == .playing || entrance == .landed }

    /// Background, bar and pill come up together as the flight starts; landing is instant.
    var entranceRise: Animation? {
        entrance == .playing ? SeleneArtBackground.rise : nil
    }

    var artReveal: ArtReveal {
        switch entrance {
        case .covered, .waiting: return .hidden
        case .playing: return .rising
        case .landed: return .shown
        }
    }

    func entranceAppear() {
        let enabled = settings.settings.introAnimation
        let due = SpotlightEntrance.plays(isFirstHome: !viewModel.homeSeen, route: router.route,
                                          reduceMotion: reduceMotion, enabled: enabled)
        viewModel.homeSeen = true
        guard due else { return landEntrance() }
        if !isCovered { uncoverEntrance() }
    }

    func uncoverEntrance() {
        guard entrance == .covered else { return }
        entrance.uncover()
        installEntranceMonitor()
        entranceWait?.cancel()
        // A breath on the moving moonlight, then the flight once the tiles' art is in (at most 1 s more).
        entranceWait = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(SpotlightEntrance.hold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            entranceBreathed = true
            if pendingTileArt == 0 { return startEntrance() }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            startEntrance()
        }
    }

    /// The tiles' art look-ups (`TileArtPendingKey`); the last one to end starts a waiting entrance.
    func tileArtPending(_ count: Int) {
        guard entrance != .landed else { return }
        pendingTileArt = count
        if count == 0, entranceBreathed { startEntrance() }
    }

    func startEntrance() {
        guard entrance == .waiting else { return }
        entranceWait?.cancel()
        entrance.start()
    }

    /// Everything in its place at once, without animation: the flight's end, input, leaving, Reduce motion.
    func landEntrance() {
        entranceWait?.cancel()
        removeEntranceMonitor()
        guard entrance != .landed else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { entrance.land() }
    }

    /// Input lands a waiting or flying entrance, then goes on as usual (the event is never taken).
    private func installEntranceMonitor() {
        guard entranceMonitor == nil else { return }
        entranceMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { event in
            landEntrance()
            return event
        }
    }

    private func removeEntranceMonitor() {
        if let entranceMonitor { NSEvent.removeMonitor(entranceMonitor) }
        entranceMonitor = nil
    }
}

extension View {
    /// One piece of Spotlight's entrance: from `flight`'s start to its place once `launched`. Every piece's clock
    /// starts at the flight's start and runs in real time, its delay counted inside (`EntranceFlight`): one start
    /// for the whole entrance, not one per tile. *Why:* with one delayed animation per tile, SwiftUI's late frames
    /// fell exactly as tiles 7, 8, 10, 13 and 20 began. Without a flight it is in its
    /// place. `outerScale` is the scale an outer effect gives it (a grown tile), so the shift stays in stage units.
    func entrance(_ flight: SpotlightEntrance.Flight?, launched: Bool, unit: CGFloat,
                  outerScale: CGFloat = 1) -> some View {
        let end = flight.map { $0.delay + $0.length } ?? 0
        let time = launched ? end : 0
        return modifier(EntranceFlight(time: time, flight: flight, unit: unit, outerScale: outerScale))
            .modifier(EntranceFade(time: time, flight: flight))
            .animation(flight.map { _ in .linear(duration: end) }, value: launched)
    }
}

/// A piece scaled about its centre and shifted, from its flight's start to its place (`Flight.move`).
struct EntranceFlight: GeometryEffect {
    /// Seconds since the entrance began (the piece's delay included).
    var time: Double
    let flight: SpotlightEntrance.Flight?
    let unit: CGFloat
    var outerScale: CGFloat = 1

    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard let flight, !flight.fadesOnly else { return ProjectionTransform() }
        let rest = 1 - flight.move(at: time - flight.delay)
        let scale = 1 - (1 - flight.fromScale) * rest
        let shift = unit * rest / max(outerScale, 0.01)
        let cx = size.width / 2, cy = size.height / 2
        return ProjectionTransform(CGAffineTransform(translationX: cx + flight.fromX * shift, y: cy + flight.fromY * shift)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -cx, y: -cy))
    }
}

/// A piece's opacity on its flight's clock (`Flight.opacity`).
struct EntranceFade: ViewModifier, Animatable {
    var time: Double
    let flight: SpotlightEntrance.Flight?

    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(flight.map { max(SpotlightView.unseenOpacity, $0.opacity(at: time - $0.delay)) } ?? 1)
    }
}
