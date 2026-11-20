import SwiftUI
import AppKit
import NXLibraryCore

/// Confirmation: the overlay, its copy, asking, dismissing and running the confirmed action.
extension GameOptionsView {
    // MARK: - Confirmation

    func confirmOverlay(_ target: ConfirmTarget) -> some View {
        let copy = confirmCopy(target)
        return ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissConfirm() }
            SeleneConfirmDialog(title: copy.title,
                                message: copy.message,
                                confirmTitle: copy.confirm,
                                focus: $confirmFocus,
                                onCancel: dismissConfirm,
                                onConfirm: runConfirm)
        }
    }

    private func confirmCopy(_ target: ConfirmTarget) -> (title: String, message: String, confirm: String) {
        switch target {
        case .removeGame:
            let copy = presentation.removal
            return (copy.title, copy.message, copy.confirmTitle)
        case .removeSources:
            let info = presentation.info(.removeSources) ?? ""
            return (L10n.text("Remove sources and build cache?"),
                    info + "\n\n" + viewModel.sourceRemovalSummary(for: current),
                    "Remove")
        }
    }

    func askConfirm(_ target: ConfirmTarget) {
        confirmFocus = .cancel
        confirm = target
    }

    func dismissConfirm() {
        guard confirm != nil else { return }
        confirm = nil
        confirmFocus = .cancel
    }

    func runConfirm() {
        guard let target = confirm else { return }
        confirm = nil
        confirmFocus = .cancel
        SoundEffectService.shared.play(.click)
        switch target {
        case .removeSources:
            viewModel.removeSources(for: current)
            onClose()
        case .removeGame:
            viewModel.deletePortedGame(current)
            onClose()
        }
    }
}
