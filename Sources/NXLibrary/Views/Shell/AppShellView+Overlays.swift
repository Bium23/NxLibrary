import SwiftUI
import AppKit
import Combine
import NXLibraryCore
import ArcanePorting

/// The shell's dialogs and notices: settings notices, welcome, install failure, Close Game, removal and the update offer.
extension AppShellView {
    // MARK: - Retry a ready build

    func settingsNoticeOverlay(_ notice: SettingsNotice) -> some View {
        ZStack {
            SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { finishSettingsNotice(choice: 0) }
            SeleneChoiceDialog(title: notice.title, message: notice.message,
                               choices: notice.retry == nil ? [notice.cancelTitle] : [notice.cancelTitle, notice.actionTitle],
                               focus: $viewModel.settingsNoticeFocus,
                               onChoose: { finishSettingsNotice(choice: $0) })
        }
    }

    /// At every launch from a temporary copy (`AppUpdate.asksToBeMoved`): that copy never updates itself, and only
    /// moving the downloaded app in the Finder fixes it. The temporary path itself is no help, so this opens Applications.
    func askToMoveIfTranslocated() {
        guard AppUpdate.asksToBeMoved(Bundle.main.bundleURL) else { return }
        viewModel.showSettingsNotice(
            title: L10n.text("Move Arcane to Applications to update"),
            message: L10n.text("macOS is running a temporary copy of Arcane, so it cannot update itself. In the Finder, move Arcane to Applications, then quit it and open it from there."),
            actionTitle: L10n.text("Open Applications"),
            cancelTitle: L10n.text("Not now"),
            retry: { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true)) })
    }

    func finishSettingsNotice(choice: Int) {
        let notice = viewModel.settingsNotice
        viewModel.settingsNotice = nil
        notice?.onDismiss?()
        if choice == 1 { notice?.retry?() }
        presentLegacyNotice()
    }

    /// Anything that comes before the welcome: Setup, dialogs, a launch, the screenshot viewer.
    private var welcomeBlocked: Bool {
        viewModel.showSetupCheck || showsSettingsNotice || showsInstallFailure
            || showsUpdateOffer || viewModel.gameToClose != nil || viewModel.gameToRemove != nil
            || viewModel.launchOverlay != nil || router.isScreenshotViewerOpen
    }

    var welcomeTrigger: [Bool] {
        [welcomeBlocked, viewModel.setupCompleted, settings.settings.welcomeArcaneShown,
         viewModel.gameWithInstallFailure != nil, viewModel.hasActiveSaveOperations]
    }

    func presentWelcomeIfDue() async {
        guard !showsWelcome, !welcomeDismissed, !welcomeBlocked, viewModel.setupCompleted,
              !settings.settings.welcomeArcaneShown else { return }
        // `hasActiveSaveOperations` is in the trigger: the welcome comes back here when the save recovery ends.
        let pending = viewModel.hasActiveSaveOperations || viewModel.saveGate.hasActiveOperations
            || viewModel.gameWithInstallFailure != nil
        guard !Task.isCancelled, !welcomeBlocked,
              ArcaneWelcome.shouldShow(setupCompleted: viewModel.setupCompleted,
                                       shown: settings.settings.welcomeArcaneShown,
                                       hasPendingRecovery: pending) else { return }
        withAnimation(reduceMotion ? nil : SeleneTheme.screen) { showsWelcome = true }
    }

    /// The welcome fades first; saving and moving to the library wait until it has gone, so no redraw of the
    /// whole shell lands in the fade's first frames (Selene does its home work once the layer has really gone).
    func closeWelcome(_ exit: ArcaneWelcome.Exit) {
        guard showsWelcome else { return }
        welcomeDismissed = true
        let finish = {
            settings.settings = ArcaneWelcome.settings(after: exit, from: settings.settings)
            if exit == .openLibrary { router.navigate(to: .library) }
            viewModel.isWelcomeOpen = false
        }
        guard !reduceMotion else {
            showsWelcome = false
            finish()
            return
        }
        withAnimation(SeleneTheme.screen) { showsWelcome = false }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(SeleneTheme.screenDuration * 1_000_000_000))
            finish()
        }
    }

    func presentLegacyNotice() {
        guard viewModel.settingsNotice == nil, let message = viewModel.alertMessage else { return }
        viewModel.alertMessage = nil
        viewModel.showSettingsNotice(title: AppIdentity.name, message: message)
    }

    func settingsNoticeInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft: viewModel.settingsNoticeFocus = 0
        case .navigateRight: viewModel.settingsNoticeFocus = viewModel.settingsNotice?.retry == nil ? 0 : 1
        case .confirm: finishSettingsNotice(choice: viewModel.settingsNoticeFocus)
        case .cancel: finishSettingsNotice(choice: 0)
        default: break
        }
    }

    func installFailureOverlay(_ game: PortedGame) -> some View {
        let app = game.pendingInstall?.finalApp ?? game.url
        let currentExists = FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path)
        return ZStack {
            SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { viewModel.gameWithInstallFailure = nil }
            SeleneConfirmDialog(title: L10n.text("Installation failed"),
                                message: L10n.format("The new build of %@ has been kept.", [String(describing: game.name)])
                                    + (currentExists ? L10n.text("\nYour current app is still available.") : L10n.text("\nYou can retry installation.")),
                                confirmTitle: "Retry", cancelTitle: L10n.text("Close"),
                                focus: $viewModel.installFailureFocus,
                                onCancel: { viewModel.gameWithInstallFailure = nil },
                                onConfirm: { viewModel.retryFailedInstallation() })
        }
    }

    func installFailureInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let next: SeleneConfirmButton = action == .navigateLeft ? .cancel : .confirm
            if viewModel.installFailureFocus != next {
                viewModel.installFailureFocus = next
                SoundEffectService.shared.play(.focus)
            }
        case .confirm:
            if viewModel.installFailureFocus == .confirm {
                viewModel.retryFailedInstallation()
            } else {
                viewModel.gameWithInstallFailure = nil
            }
        case .cancel: viewModel.gameWithInstallFailure = nil
        default: break
        }
    }

    // MARK: - Close Game confirmation

    func closeGameOverlay(_ game: PortedGame) -> some View {
        ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { viewModel.dismissCloseGame() }
            SeleneConfirmDialog(title: L10n.format("Close %@?", [String(describing: game.name)]),
                                message: L10n.text("Unsaved progress in the game will be lost."),
                                confirmTitle: "Close",
                                focus: $viewModel.closeGameFocus,
                                onCancel: { viewModel.dismissCloseGame() },
                                onConfirm: confirmCloseGame)
        }
    }

    /// Input while the Close Game confirmation is open: Left and Right pick a pill, A runs it, B cancels.
    func closeGameInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let next: SeleneConfirmButton = action == .navigateLeft ? .cancel : .confirm
            if viewModel.closeGameFocus != next {
                viewModel.closeGameFocus = next
                SoundEffectService.shared.play(.focus)
            }
        case .confirm:
            if viewModel.closeGameFocus == .confirm {
                confirmCloseGame()
            } else {
                viewModel.dismissCloseGame()
            }
        case .cancel:
            viewModel.dismissCloseGame()
        default:
            break
        }
    }

    // MARK: - Delete after a failed porting

    func removeGameOverlay(_ game: PortedGame) -> some View {
        ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { viewModel.dismissRemoveGame() }
            SeleneConfirmDialog(title: L10n.format("Delete %@?", [String(describing: game.name)]),
                                message: L10n.text("It leaves the library. Your game files and the build cache stay on disk."),
                                confirmTitle: "Delete",
                                focus: $viewModel.removeGameFocus,
                                onCancel: { viewModel.dismissRemoveGame() },
                                onConfirm: { viewModel.confirmRemoveGame() })
        }
    }

    // MARK: - A newer release at launch

    func updateOfferOverlay() -> some View {
        ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { updater.later() }
            AppUpdateDialog(updater: updater, requirementNotes: updater.dialogRelease.map {
                AppUpdate.requirementNotes($0.requirements,
                    installedXcode: setup.environmentStatus?.xcodeVersion,
                    currentEngine: viewModel.pinnedEngineCommit)
            } ?? [], blockedReason: updater.blockedReason())
        }
    }

    func updateOfferInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let next: SeleneConfirmButton = action == .navigateLeft && updater.dialogHasSecondaryButton ? .cancel : .confirm
            if updater.offerFocus != next {
                updater.offerFocus = next
                SoundEffectService.shared.play(.focus)
            }
        case .confirm:
            SoundEffectService.shared.play(.click)
            if updater.offerFocus == .confirm { updater.confirmDialog() } else { updater.later() }
        case .cancel:
            updater.later()
        case .navigateUp, .navigateDown, .jumpToStart, .jumpToEnd:
            let last = max(0, (updater.dialogRelease?.notes.components(separatedBy: "\n").count ?? 1) - 1)
            switch action {
            case .jumpToStart: updater.notesScroll = 0
            case .jumpToEnd: updater.notesScroll = last
            default: updater.notesScroll = min(last, max(0, updater.notesScroll + (action == .navigateUp ? -3 : 3)))
            }
        default:
            break
        }
    }

    func removeGameInput(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let next: SeleneConfirmButton = action == .navigateLeft ? .cancel : .confirm
            if viewModel.removeGameFocus != next {
                viewModel.removeGameFocus = next
                SoundEffectService.shared.play(.focus)
            }
        case .confirm:
            SoundEffectService.shared.play(.click)
            if viewModel.removeGameFocus == .confirm {
                viewModel.confirmRemoveGame()
            } else {
                viewModel.dismissRemoveGame()
            }
        case .cancel:
            viewModel.dismissRemoveGame()
        default:
            break
        }
    }

    private func confirmCloseGame() {
        guard let game = viewModel.gameToClose else { return }
        viewModel.dismissCloseGame()
        SoundEffectService.shared.play(.click)
        runningGames.close(game)
    }
}
