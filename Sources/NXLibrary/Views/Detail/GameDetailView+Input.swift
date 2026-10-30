import SwiftUI
import AppKit
import NXLibraryCore

/// Details' controller, keyboard, scroll-wheel and pointer input. The guards
/// match Spotlight's and Collection's: no key or wheel event goes to the page
/// while an alert, a sheet, the menu or the screenshot viewer owns the keyboard.
extension GameDetailView {
    // MARK: - Controller

    func handle(_ action: GamepadAction) {
        if viewer != nil { return handleViewer(action) }
        var moved = false
        switch action {
        case .navigateLeft: moved = moveFocus { $0.left(in: $1) }
        case .navigateRight: moved = moveFocus { $0.right(in: $1) }
        case .navigateUp: moved = moveFocus { $0.up(in: $1) }
        case .navigateDown: moved = moveFocus { $0.down(in: $1) }
        case .confirm: activateFocused()
        case .cancel: router.back()
        case .secondaryAction, .contextAction: openOptions()
        default: break
        }
        if moved { SoundEffectService.shared.play(.focus) }
    }

    /// Applies a focus move; returns whether the focus moved.
    @discardableResult
    func moveFocus(_ move: (inout DetailsFocus, DetailsFocus.Bands) -> Bool) -> Bool {
        var next = focus
        let moved = move(&next, currentModel.bands)
        if next != focus { focus = next }
        return moved
    }

    /// Sets the focus from a pointer press or hover, clamped to what the band holds.
    func focusPointer(zone: Int, index: Int, bands: DetailsFocus.Bands) {
        var next = focus
        next.focus(zone: zone, index: index, in: bands)
        if next != focus {
            focus = next
            SoundEffectService.shared.play(.focus)
        }
    }

    /// Hover moves focus only inside the band already in focus; a peeking band
    /// changes zone on press, not on hover.
    func hoverPill(_ index: Int) {
        guard focus.zone == DetailsFocus.topZone, focus.pill != index else { return }
        var next = focus
        next.focus(zone: DetailsFocus.topZone, index: index, in: currentModel.bands)
        if next != focus { focus = next }
    }

    /// Press on a top-block pill: focus it and run it (Play, Build or Resume; Game options or Close Game).
    func pressPill(_ index: Int) {
        var next = focus
        next.focus(zone: DetailsFocus.topZone, index: index, in: currentModel.bands)
        if next != focus { focus = next }
        runPill(index)
    }

    func runPill(_ index: Int) {
        switch index {
        case 0: primaryAction()
        case 1: secondaryAction()
        default: toggleFavorite()
        }
    }

    func toggleFavorite() {
        SoundEffectService.shared.play(.click)
        viewModel.toggleFavorite(game)
    }

    /// Hover moves the action focus only while Build & Sources is in focus.
    func hoverRow(_ index: Int) {
        guard focus.zone == DetailsFocus.actionsZone, focus.action != index else { return }
        var next = focus
        next.focus(zone: DetailsFocus.actionsZone, index: index, in: currentModel.bands)
        if next != focus { focus = next }
    }

    /// Press on a row: when Build & Sources is in focus it runs the row (the
    /// row's own path explains a refusal, e.g. the Metal gate); otherwise the
    /// press first brings that band into focus.
    func pressRow(_ index: Int) {
        guard focus.zone == DetailsFocus.actionsZone else {
            focusPointer(zone: DetailsFocus.actionsZone, index: index, bands: currentModel.bands)
            return
        }
        hoverRow(index)
        let rows = currentModel.rows
        guard index < rows.count else { return }
        rows[index].action()
    }

    func activateFocused() {
        let model = currentModel
        switch focus.zone {
        case DetailsFocus.topZone:
            runPill(focus.pill)
        case DetailsFocus.screenshotsZone:
            openViewer(at: focus.shot)
        case DetailsFocus.actionsZone:
            guard focus.action < model.rows.count else { return }
            model.rows[focus.action].action()
        case DetailsFocus.moreZone:
            guard focus.more < model.more.count else { return }
            selectOnSpotlight(model.more[focus.more])
        default:
            break
        }
    }

    /// Resume while the game runs; otherwise Play when the game is built, or Build (which refuses with a sound when it cannot run).
    func primaryAction() {
        if runningGames.isRunning(game) {
            SoundEffectService.shared.play(.click)
            runningGames.resume(game)
        } else if currentModel.presentation.canPlay {
            SoundEffectService.shared.play(.click)
            viewModel.launchGame(game)
        } else {
            rebuild()
        }
    }

    func rebuild() {
        guard currentModel.presentation.canRebuild else {
            SoundEffectService.shared.play(.error)
            return
        }
        SoundEffectService.shared.play(.click)
        viewModel.startBuild(for: game)
        if viewModel.isBuilding {
            router.openAddGame()
        }
    }

    /// The second top pill: Close Game while the game runs (after the confirmation), else Game options.
    func secondaryAction() {
        if runningGames.isRunning(game) {
            SoundEffectService.shared.play(.click)
            viewModel.askCloseGame(game)
        } else {
            openOptions()
        }
    }

    func openOptions() {
        SoundEffectService.shared.play(.click)
        viewModel.openGameOptions(game, from: .details)
    }

    /// A More like this game: Spotlight opens with it selected (All games when its filter hides it).
    func selectOnSpotlight(_ target: PortedGame) {
        SoundEffectService.shared.play(.click)
        router.requestSpotlightSelect(target.id)
        router.showLibrary()
    }

    // MARK: - Screenshot viewer

    func openViewer(at index: Int) {
        let urls = currentModel.screenshots
        guard !urls.isEmpty else { return }
        viewer = ViewerContext(titleID: game.titleId ?? game.uniqueKey, urls: urls,
                               state: ScreenshotViewerState(count: urls.count, start: index))
        SoundEffectService.shared.play(.click)
    }

    /// Closing returns the focus to the screenshot last viewed.
    func closeViewer() {
        guard let context = viewer else { return }
        viewer = nil
        var next = focus
        next.focus(zone: DetailsFocus.screenshotsZone, index: context.state.index, in: currentModel.bands)
        focus = next
        SoundEffectService.shared.play(.focus)
    }

    func handleViewer(_ action: GamepadAction) {
        guard var context = viewer else { return }
        switch ScreenshotViewer.handle(action, state: &context.state) {
        case .moved:
            viewer = context
            SoundEffectService.shared.play(.focus)
        case .close:
            closeViewer()
        case .ignored:
            break
        }
    }

    // MARK: - Keyboard and wheel

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { event in
            guard !router.isMenuPresented,
                  case .detail(let id) = router.route, id == game.id,
                  viewModel.alertMessage == nil,
                  viewModel.gameForSettingsSheet == nil,
                  viewModel.gameToClose == nil,
                  !viewModel.showSetupCheck,
                  !viewModel.showInstallerSheet,
                  let window = event.window,
                  !window.isSheet,
                  window.attachedSheet == nil,
                  NSApp.modalWindow == nil,
                  !(window.firstResponder is NSText) else { return event }
            if event.type == .scrollWheel {
                return handleWheel(event)
            }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return event }
            if viewer != nil {
                // The viewer owns the keyboard: arrows page, Esc closes, the rest is swallowed.
                switch event.keyCode {
                case 123: handle(.navigateLeft)
                case 124: handle(.navigateRight)
                case 53: handle(.cancel)
                case 12: handle(.tabPrevious)
                case 14: handle(.tabNext)
                case 36, 49, 125, 126, 7, 16, 48: break
                default: return event
                }
                return nil
            }
            let action: GamepadAction
            switch event.keyCode {
            case 123: action = .navigateLeft
            case 124: action = .navigateRight
            case 125: action = .navigateDown
            case 126: action = .navigateUp
            case 36, 49: action = .confirm
            case 53: action = .cancel           // Esc: back to where Details was opened from
            case 7: action = .secondaryAction   // X
            case 16: action = .contextAction    // Y
            default: return event
            }
            handle(action)
            return nil
        }
    }

    /// The wheel moves between bands, except while the description is open: then it scrolls the text.
    private func handleWheel(_ event: NSEvent) -> NSEvent? {
        guard !expanded else { return event }
        let dy = event.scrollingDeltaY
        guard abs(dy) > abs(event.scrollingDeltaX), event.momentumPhase.isEmpty else { return nil }
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 6 : 1
        var gate = wheel
        let action = gate.feed(dy, at: event.timestamp, threshold: threshold)
        wheel = gate
        if let action { handle(action) }
        return nil
    }

    func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
