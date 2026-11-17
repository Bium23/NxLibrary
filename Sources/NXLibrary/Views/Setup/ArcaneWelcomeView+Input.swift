import SwiftUI
import AppKit
import NXLibraryCore

extension ArcaneWelcomeView {
    /// Controller actions and the mapped keys while the welcome is up: arrows between Add, Not now and
    /// Open library, A on the one in focus, B or Esc closes.
    func handle(_ action: GamepadAction) {
        guard NSApp.modalWindow == nil else { return }
        switch action {
        case .navigateLeft: move(to: focus.moved(.left, offer: offer))
        case .navigateRight: move(to: focus.moved(.right, offer: offer))
        case .navigateUp: move(to: focus.moved(.up, offer: offer))
        case .navigateDown: move(to: focus.moved(.down, offer: offer))
        case .confirm: activate(focus)
        case .cancel:
            SoundEffectService.shared.play(.back)
            onExit(.back)
        default: break
        }
    }

    func move(to next: ArcaneWelcome.Focus) {
        guard focus != next else { return }
        focus = next
        moved = true
        SoundEffectService.shared.play(.focus)
    }

    func activate(_ target: ArcaneWelcome.Focus) {
        guard NSApp.modalWindow == nil else { return }
        switch target {
        case .add where offer != nil:
            SoundEffectService.shared.play(.click)
            onAddSteam()
            offerAnswered = true
        case .notNow where offer != nil:
            SoundEffectService.shared.play(.click)
            offerAnswered = true
        case .openLibrary:
            SoundEffectService.shared.play(.click)
            onExit(.openLibrary)
        default:
            SoundEffectService.shared.play(.error)
        }
    }
}
