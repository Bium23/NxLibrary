import SwiftUI
import AppKit
import Combine
import NXLibraryCore

/// Keyboard equivalents of the controller gestures, the menu's input and its actions.
extension AppShellView {
    /// App-level monitor for the keyboard equivalents of the controller gestures.
    /// Handles only Tab, Cmd+F, Cmd+, , Home and End; every other event passes through.
    func installGestureKeyMonitor() {
        guard gestureKeyMonitor == nil else { return }
        gestureKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [router, viewModel] event in
            if nativeMenus.isTracking { return event }
            // The screenshot viewer owns the keyboard (its own monitor handles it); no navigating underneath.
            if router.isScreenshotViewerOpen { return event }
            // An alert or another window's sheet owns Return and Esc.
            if nativeDialogOwnsInput
                || event.window?.attachedSheet != nil || event.window?.isSheet == true {
                return event
            }
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            // The Setup check and the welcome take the keyboard: arrows, Return, Space and Esc go to them.
            if viewModel.showSetupCheck || (showsWelcome && !showsSettingsNotice && !showsInstallFailure
                                            && !showsUpdateOffer && viewModel.gameToClose == nil
                                            && viewModel.gameToRemove == nil) {
                guard mods.isEmpty, !(event.window?.firstResponder is NSText) else { return event }
                let setupAction: GamepadAction?
                switch event.keyCode {
                case 123: setupAction = .navigateLeft
                case 124: setupAction = .navigateRight
                case 125: setupAction = .navigateDown
                case 126: setupAction = .navigateUp
                case 36, 76, 49: setupAction = .confirm
                case 53: setupAction = .cancel
                default: setupAction = nil
                }
                guard let setupAction else { return nil }
                GameControllerService.shared.onAction?(setupAction)
                return nil
            }
            // The Close Game and Delete confirmations take the keyboard: arrows, Return, Space and Esc go to them.
            if viewModel.gameToClose != nil || viewModel.gameToRemove != nil || showsUpdateOffer || showsInstallFailure || showsSettingsNotice, mods.isEmpty {
                let closeAction: GamepadAction?
                switch event.keyCode {
                case 123: closeAction = .navigateLeft
                case 124: closeAction = .navigateRight
                case 125: closeAction = showsUpdateOffer ? .navigateDown : nil
                case 126: closeAction = showsUpdateOffer ? .navigateUp : nil
                case 36, 76, 49: closeAction = .confirm
                case 53: closeAction = .cancel
                default: closeAction = nil
                }
                if let closeAction {
                    GameControllerService.shared.onAction?(closeAction)
                    return nil
                }
            }
            // The open control center takes the keyboard: arrows, Return, Space and Esc go to the menu,
            // and no screen underneath sees them.
            // Typing in a menu's text field (the Theme screen's search): keys go to the field, Esc leaves it.
            if router.isMenuPresented, event.window?.firstResponder is NSText, event.keyCode != 53 {
                return event
            }
            if router.isMenuPresented, mods.isEmpty {
                let menuAction: GamepadAction?
                switch event.keyCode {
                case 123: menuAction = .navigateLeft     // Left arrow
                case 124: menuAction = .navigateRight    // Right arrow
                case 125: menuAction = .navigateDown     // Down arrow
                case 126: menuAction = .navigateUp       // Up arrow
                case 36, 76, 49: menuAction = .confirm   // Return, keypad Enter, Space
                case 53: menuAction = .cancel            // Esc
                case 51: menuAction = router.isThemePickerOpen ? .contextAction : nil   // Delete: remove your own wallpaper
                case 12: menuAction = router.isThemePickerOpen ? .tabPrevious : nil     // Q: Wallpapers / Live, as LB
                case 14: menuAction = router.isThemePickerOpen ? .tabNext : nil         // E: as RB
                case 7: menuAction = router.isThemePickerOpen ? .secondaryAction : nil  // X: open the page
                case 16: menuAction = router.isThemePickerOpen ? .contextAction : nil   // Y: remove
                default: menuAction = nil
                }
                if let menuAction {
                    GameControllerService.shared.onAction?(menuAction)
                    return nil
                }
            }
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let typing = event.window?.firstResponder is NSText
            var action: GamepadAction?
            switch (event.keyCode, key, mods) {
            case (48, _, []):                       // Tab
                if typing { return event }
                action = .view
            case (_, "f", [.command]):              // Cmd+F
                if typing { return event }
                action = .viewHold
            case (_, ",", [.command]):              // Cmd+,
                // Same as holding Menu. Consumed, so the menu-bar Settings command does not open Settings a second time.
                action = .menuHold
            case (115, _, []):                      // Home
                if typing { return event }
                action = .jumpToStart
            case (119, _, []):                      // End
                if typing { return event }
                action = .jumpToEnd
            default:
                return event
            }
            if let action { GameControllerService.shared.onAction?(action) }
            return nil
        }
    }

    func removeGestureKeyMonitor() {
        if let monitor = gestureKeyMonitor { NSEvent.removeMonitor(monitor) }
        gestureKeyMonitor = nil
    }

    /// Input while the control center is open: arrows move, A selects, B (or Esc) closes the Power pills
    /// first and then the menu, Menu closes it, and hold Menu closes it and opens Settings.
    func menuInput(_ action: GamepadAction) {
        // The Theme screen takes everything but Menu, which closes the whole menu.
        if router.isThemePickerOpen, action != .menu, action != .menuHold {
            NotificationCenter.default.post(name: .nxThemePickerGamepadAction, object: action)
            return
        }
        switch action {
        case .navigateLeft:
            router.moveMenu(by: -1)
        case .navigateRight:
            router.moveMenu(by: 1)
        case .navigateUp:
            router.movePowerMenu(by: -1)
        case .navigateDown:
            router.movePowerMenu(by: 1)
        case .confirm:
            if router.menuSelection.isPowerOpen {
                runPower(router.menuSelection.power)
            } else {
                runMenuAction(router.menuSelection.selected)
            }
        case .cancel:
            if router.menuSelection.isPowerOpen {
                router.closePowerMenu()
            } else {
                router.closeMenu()
            }
        case .menu:
            router.closeMenu()
        case .menuHold:
            router.closeMenu()
            router.openSettings(.startUp)
        default:
            break
        }
    }

    /// A row button. The menu closes before it navigates; Power only opens or closes its
    /// pills, and Theme opens its screen in place of the row.
    func runMenuAction(_ action: MenuAction) {
        switch action {
        case .power:
            if router.menuSelection.isPowerOpen {
                router.closePowerMenu()
            } else {
                router.openPowerMenu()
            }
        case .addGame:
            router.closeMenu()
            openFreshAddGame()
        case .refreshLibrary:
            router.closeMenu()
            viewModel.refreshLibrary()
            if sources.configuration.isEnabled { sources.refresh() }
        case .manageSources:
            router.closeMenu()
            router.openSettings(.sources)
        case .settings:
            router.closeMenu()
            router.openSettings(.startUp)
        case .theme:
            // The menu's own screen: the theme's colors, then the background.
            router.isThemePickerOpen = true
        case .console:
            router.closeMenu()
            router.openConsole()
        case .setupCheck:
            router.closeMenu()
            viewModel.reopenSetup()
        }
    }

    func runPower(_ action: PowerAction) {
        switch action {
        case .quit:
            router.closeMenu()
            NSApplication.shared.terminate(nil)
        case .hide:
            router.closeMenu()
            NSApplication.shared.hide(nil)
        case .relaunch:
            relaunchApp()
        }
    }

    /// Starts a helper that waits for this process to exit and then opens the bundle again, then quits.
    /// A second instance cannot be opened while this one runs (LSMultipleInstancesProhibited), so
    /// the new one must start after this one has gone.
    private func relaunchApp() {
        router.closeMenu()
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c",
            "i=0; while kill -0 \"$1\" 2>/dev/null && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done; exec /usr/bin/open \"$2\"",
            "relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundleURL.path
        ]
        do {
            try helper.run()
        } catch {
            viewModel.alertMessage = L10n.format("Arcane could not restart: %@", [String(describing: error.localizedDescription)])
            return
        }
        AppDelegate.relaunchScheduled = true
        NSApplication.shared.terminate(nil)
    }
}
