import SwiftUI
import AppKit
import NXLibraryCore

extension FoundGamesSetupView {
    /// Controller actions and the mapped keys while `found` is up: Up/Down between the rows, A on the one in focus.
    func handle(_ action: GamepadAction) {
        guard viewModel.showSetupCheck, viewModel.firstRunSetup.page == .found,
              NSApp.modalWindow == nil, viewModel.alertMessage == nil else { return }
        switch action {
        case .navigateUp: move(to: focus.movedOnFound(.up, hasSteam: hasSteam))
        case .navigateDown: move(to: focus.movedOnFound(.down, hasSteam: hasSteam))
        case .confirm: activate(focus)
        default: break
        }
    }

    func move(to next: FirstRunSetup.Focus) {
        guard focus != next else { return }
        focus = next
        SoundEffectService.shared.play(.focus)
    }

    func activate(_ target: FirstRunSetup.Focus) {
        guard viewModel.showSetupCheck, viewModel.firstRunSetup.page == .found, NSApp.modalWindow == nil else { return }
        move(to: target)
        switch target {
        case .steamToggle where findings?.steamReadFailed == true:
            SoundEffectService.shared.play(.click)
            reader.start(steamRoot: steamRoot, appsFolder: viewModel.gameAppsFolder)
        case .steamToggle where steamCount != nil:
            viewModel.chooseSteamOnFound(!steamOn)
            SoundEffectService.shared.play(.key)
        case .portingCard:
            SoundEffectService.shared.play(.click)
            viewModel.openPortingFromFound()
        case .openLibrary:
            reader.cancel()
            SoundEffectService.shared.play(.click)
            onOpenLibrary(portedCount > 0)
        default:
            SoundEffectService.shared.play(.error)
        }
    }
}
