import SwiftUI
import NXLibraryCore

/// Spotlight's entrance, the first time the home shows after launch (`SpotlightEntrance`). While the intro or the
/// welcome covers the screen, the row, the bar, the pill, the info and the art stay hidden and the moonlight still,
/// so nothing under the cover costs a frame. Once it has gone, the entrance waits for the visible tiles' art (at
/// most 1 s), then plays. Every later visit, Reduce motion and a launch on another screen land it at once.
extension SpotlightView {
    /// The intro, the welcome until its fade has ended, or Setup (the first launch's pages come before the home).
    var isCovered: Bool { router.isIntroShowing || viewModel.isWelcomeOpen || viewModel.showSetupCheck }

    func entranceAppear() {
        let due = SpotlightEntrance.plays(isFirstHome: !viewModel.homeSeen, route: router.route,
                                          reduceMotion: reduceMotion)
        viewModel.homeSeen = true
        guard due else { return landEntrance() }
        if !isCovered { uncoverEntrance() }
    }

    func uncoverEntrance() {
        guard entrance == .covered else { return }
        entrance.uncover()
        entranceWait?.cancel()
        entranceWait = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            startEntrance()
        }
        if pendingTileArt == 0 { startEntrance() }
    }

    /// The tiles' art look-ups (`TileArtPendingKey`); the last one to end starts a waiting entrance.
    func tileArtPending(_ count: Int) {
        guard entrance != .landed else { return }
        pendingTileArt = count
        if count == 0 { startEntrance() }
    }

    func startEntrance() {
        guard entrance == .waiting else { return }
        entranceWait?.cancel()
        entrance.start()
        landEntrance()
    }

    /// Everything in its place at once, without animation.
    func landEntrance() {
        entranceWait?.cancel()
        guard entrance != .landed else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { entrance.land() }
    }
}
