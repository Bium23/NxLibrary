import SwiftUI
import NXLibraryCore

/// Which pill of a confirmation dialog has focus.
enum SeleneConfirmButton: Equatable {
    case cancel
    case confirm
}

/// Selene's confirmation card (its dialogs: a 640u card, centred title and text,
/// two pills). Cancel is the focused pill by default, so a stray A keeps the item.
/// The caller owns input: it moves `focus` with Left/Right or hover, and acts on
/// the two closures. Reused by Game options now and by later confirmations.
struct SeleneConfirmDialog: View {
    @Environment(\.seleneCanvas) private var canvas

    let title: String
    let message: String
    let confirmTitle: String
    @Binding var focus: SeleneConfirmButton
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .seleneFont(34, .semibold)
                .foregroundColor(SeleneTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .seleneFont(19)
                .foregroundColor(SeleneTheme.ink75)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, canvas.u(14))
            HStack(spacing: canvas.u(22)) {
                SelenePillButton(title: "Cancel", focused: focus == .cancel, action: onCancel)
                    .onHover { if $0 { focus = .cancel } }
                    .accessibilityLabel("Cancel")
                SelenePillButton(title: confirmTitle, focused: focus == .confirm, action: onConfirm)
                    .onHover { if $0 { focus = .confirm } }
                    .accessibilityLabel(confirmTitle)
            }
            .padding(.top, canvas.u(34))
        }
        .multilineTextAlignment(.center)
        .padding(.leading, canvas.u(40))
        .padding(.top, canvas.u(40))
        .padding(.trailing, canvas.u(40))
        .padding(.bottom, canvas.u(36))
        .frame(width: canvas.u(640))
        .background(
            RoundedRectangle(cornerRadius: canvas.u(28), style: .continuous)
                .fill(SeleneTheme.glassCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: canvas.u(28), style: .continuous)
                .strokeBorder(SeleneTheme.ink.opacity(0.16), lineWidth: max(1, canvas.u(1)))
        )
        .clipShape(RoundedRectangle(cornerRadius: canvas.u(28), style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: canvas.u(30))
    }
}
