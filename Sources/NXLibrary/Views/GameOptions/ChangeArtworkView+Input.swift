import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import NXLibraryCore

/// Input: tabs, moving the focus, back and close, choosing, the gamepad and the key monitor.
extension ChangeArtworkView {
    // MARK: - Input

    func select(_ tab: ArtworkSlot) {
        guard tab != slot else { return }
        slot = tab
        focus = 0
        message = nil
        SoundEffectService.shared.play(.focus)
    }

    private func move(_ direction: ArtworkPickerFocus.Direction) {
        let count = tiles.count
        if browsing != nil {
            if focus < 0 {
                guard direction == .down, count > 0 else { return }
                fieldFocused = false
                focus = 0
                SoundEffectService.shared.play(.focus)
                return
            }
            if direction == .up, focus < columns {
                focus = -1
                SoundEffectService.shared.play(.focus)
                return
            }
        }
        let next = ArtworkPickerFocus.moved(focus, by: direction, count: count, columns: columns)
        guard next != focus else { return }
        focus = next
        SoundEffectService.shared.play(.focus)
    }

    /// Back: out of the source, or out of the picker.
    func back() {
        if browsing != nil {
            SoundEffectService.shared.play(.focus)
            closeBrowse()
        } else {
            close()
        }
    }

    private func close() {
        SoundEffectService.shared.play(.focus)
        onClose()
    }

    func chooseFocused() {
        if browsing != nil, focus < 0 {
            fieldFocused = true
            return
        }
        let tiles = self.tiles
        guard tiles.indices.contains(focus) else { return }
        choose(tiles[focus])
    }

    func handleGamepad(_ action: GamepadAction) {
        // The key dialog reads the controller itself.
        if viewModel.isEditingSteamGridDBKey { return }
        if askAppIcon {
            switch action {
            case .navigateLeft, .navigateRight:
                let next: SeleneConfirmButton = action == .navigateLeft ? .cancel : .confirm
                if appIconFocus != next {
                    appIconFocus = next
                    SoundEffectService.shared.play(.focus)
                }
            case .confirm: answerAppIcon(appIconFocus == .confirm)
            case .cancel:
                askAppIcon = false
                // Back dismisses the location question. A newly chosen image still follows the saved scope.
                if !editingIconLocation, let macApp { appIcon.appIconPickChanged(for: macApp, removed: false) }
                SoundEffectService.shared.play(.focus)
            default: break
            }
            return
        }
        switch action {
        case .navigateUp: move(.up)
        case .navigateDown: move(.down)
        case .navigateLeft: move(.left)
        case .navigateRight: move(.right)
        case .tabPrevious: select(ArtworkPickerFocus.slot(after: slot, by: -1))
        case .tabNext: select(ArtworkPickerFocus.slot(after: slot, by: 1))
        case .confirm: chooseFocused()
        case .secondaryAction: browsing != nil ? openPage() : close()
        case .cancel: back()
        case .menu: close()
        default: break
        }
    }

    /// Arrows, Return/Space, Esc, Q/E for the tabs (L and R on the keyboard) and X for the source's page.
    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.optionsGameID == subject.id, !viewModel.isEditingSteamGridDBKey,
                  let window = event.window, !window.isSheet, window.attachedSheet == nil,
                  NSApp.modalWindow == nil, !(window.firstResponder is NSText) else { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            if askAppIcon {
                switch event.keyCode {
                case 123: handleGamepad(.navigateLeft)
                case 124: handleGamepad(.navigateRight)
                case 36, 76, 49: handleGamepad(.confirm)
                case 53: handleGamepad(.cancel)
                default: break
                }
                return nil
            }
            switch event.keyCode {
            case 126: move(.up)
            case 125: move(.down)
            case 123: move(.left)
            case 124: move(.right)
            case 12: select(ArtworkPickerFocus.slot(after: slot, by: -1))
            case 14: select(ArtworkPickerFocus.slot(after: slot, by: 1))
            case 7 where browsing != nil: openPage()
            case 36, 76, 49: chooseFocused()
            case 53: back()
            default: return event
            }
            return nil
        }
    }

    func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
