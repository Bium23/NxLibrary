import SwiftUI
import AppKit
import NXLibraryCore

/// Input: the key monitor, the wheel, the gamepad, navigation, back and activating a row.
extension GameOptionsView {
    // MARK: - Input

    /// Nothing in the panel takes key focus, so `onMoveCommand` cannot be relied on:
    /// a monitor maps arrows, Return/Space and Esc, and turns the wheel into steps.
    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { event in
            guard viewModel.gameForSettingsSheet?.id == game.id,
                  !viewModel.isUpdateOfferOpen,
                  !viewModel.isWelcomeOpen,
                  !NativeMenuCommands.shared.isTracking,
                  !panelOpen,
                  viewModel.gameToClose == nil,
                  viewModel.gameWithInstallFailure == nil,
                  viewModel.alertMessage == nil, viewModel.settingsNotice == nil,
                  let window = event.window,
                  !window.isSheet,
                  window.attachedSheet == nil,
                  NSApp.modalWindow == nil,
                  !(window.firstResponder is NSText) else { return event }
            if event.type == .scrollWheel { return scroll(with: event) }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return event }
            switch event.keyCode {
            case 126: navigate(by: -1)
            case 125: navigate(by: 1)
            case 123: horizontal(by: -1)
            case 124: horizontal(by: 1)
            case 36, 76, 49: activateFocused()
            case 53: back()
            case 16: toggleInfo()   // Y
            default: return event
            }
            return nil
        }
    }

    func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// The list scrolls natively; 0.3 s after the last wheel or trackpad event
    /// (momentum included) the focus settles on a row in view.
    private func scroll(with event: NSEvent) -> NSEvent? {
        guard confirm == nil else { return nil }
        scrollBox.settle?.cancel()
        scrollBox.window = event.window
        scrollBox.pointer = event.locationInWindow
        let work = DispatchWorkItem { settleFocusOnScroll() }
        scrollBox.settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        return event
    }

    /// Keeps the focus if its row is still fully in view; otherwise picks the
    /// row nearest the middle of the list, without scrolling to it.
    private func settleFocusOnScroll() {
        // Where the list is scrolled to is read from its NSScrollView, once, now:
        // measuring it on every frame made the scroll stutter.
        guard let clip = scrollBox.clipView() else { return }
        let viewport = clip.bounds.height
        let top = clip.isFlipped ? clip.bounds.minY
            : (clip.documentView?.frame.height ?? 0) - clip.bounds.maxY
        guard viewport > 0 else { return }
        let rows = self.rows
        let frames = scrollBox.frames
            .filter { rows.contains($0.key) }
            .mapValues { $0.offsetBy(dx: 0, dy: -top) }
        if let row = focusedRow, let frame = frames[row], frame.minY >= 0, frame.maxY <= viewport { return }
        let inView = frames.filter { $0.value.maxY > 0 && $0.value.minY < viewport }
        guard let nearest = inView.min(by: {
            abs($0.value.midY - viewport / 2) < abs($1.value.midY - viewport / 2)
        })?.key, nearest != focusedRow else { return }
        scrollBox.holdScroll = true
        setFocus(nearest)
        SoundEffectService.shared.play(.focus)
    }

    func handleGamepad(_ action: GamepadAction) {
        // Change artwork and Change metadata read the same notifications while open.
        guard !panelOpen else { return }
        switch action {
        case .navigateUp: navigate(by: -1)
        case .navigateDown: navigate(by: 1)
        case .navigateLeft: horizontal(by: -1)
        case .navigateRight: horizontal(by: 1)
        case .confirm: activateFocused()
        case .cancel: back()
        case .contextAction: toggleInfo()
        case .secondaryAction, .menu:
            if confirm != nil { dismissConfirm() } else { onClose() }
        default: break
        }
    }

    private func navigate(by delta: Int) {
        guard confirm == nil else { return }
        moveFocus(by: delta)
    }

    /// Left/Right: the dialog's pills, or the value of a focused choice row.
    private func horizontal(by delta: Int) {
        if confirm != nil {
            let next: SeleneConfirmButton = delta < 0 ? .cancel : .confirm
            if next != confirmFocus {
                confirmFocus = next
                SoundEffectService.shared.play(.focus)
            }
            return
        }
        guard let row = focusedRow, row.isChoice else { return }
        adjust(row, by: delta)
    }

    /// B: close an open explanation, then leave the dialog, then Edit details, then close.
    func back() {
        if infoRow != nil {
            infoRow = nil
        } else if confirm != nil {
            dismissConfirm()
        } else if level == .editDetails {
            leaveEditDetails()
        } else {
            onClose()
        }
    }

    /// A on the focused row (also Return and Space).
    private func activateFocused() {
        infoRow = nil
        if confirm != nil {
            if confirmFocus == .confirm { runConfirm() } else { dismissConfirm() }
            return
        }
        guard let row = focusedRow else { return }
        perform(row)
    }

    func activate(_ row: GameOptionsRow) {
        guard confirm == nil else { return }
        infoRow = nil
        setFocus(row)
        perform(row)
    }
}
