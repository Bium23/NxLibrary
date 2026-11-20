import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

/// The Mods band and the mod store that opens from it.
extension SpotlightView {
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
}
