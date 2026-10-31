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
struct SeleneConfirmDialog<Detail: View>: View {
    @Environment(\.seleneCanvas) private var canvas

    let title: String
    let message: String
    let confirmTitle: String
    var cancelTitle = "Cancel"
    @Binding var focus: SeleneConfirmButton
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder var detailContent: () -> Detail

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
            detailContent()
            HStack(spacing: canvas.u(22)) {
                SelenePillButton(title: cancelTitle, focused: focus == .cancel, action: onCancel)
                    .onHover { if $0 { focus = .cancel } }
                    .accessibilityLabel(cancelTitle)
                SelenePillButton(title: confirmTitle, focused: focus == .confirm, action: onConfirm)
                    .onHover { if $0 { focus = .confirm } }
                    .accessibilityLabel(confirmTitle)
            }
            .padding(.top, canvas.u(34))
        }
        .modifier(SeleneDialogCard())
    }
}

extension SeleneConfirmDialog where Detail == SeleneDialogNotes {
    init(title: String, message: String, confirmTitle: String, cancelTitle: String = "Cancel",
         detail: String? = nil, focus: Binding<SeleneConfirmButton>,
         onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.init(title: title, message: message, confirmTitle: confirmTitle, cancelTitle: cancelTitle,
                  focus: focus, onCancel: onCancel, onConfirm: onConfirm) {
            SeleneDialogNotes(detail: detail)
        }
    }
}

/// Plain release notes keep their own scrolling text layout.
struct SeleneDialogNotes: View {
    @Environment(\.seleneCanvas) private var canvas
    let detail: String?

    var body: some View {
        if let detail, !detail.isEmpty {
            ScrollView {
                Text(detail)
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink75)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(canvas.u(16))
            }
            .frame(maxHeight: canvas.u(260))
            .background(
                RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
                    .fill(SeleneTheme.glassLight)
            )
            .padding(.top, canvas.u(20))
        }
    }
}

/// The dialog card both dialogs wear: 640u, glass, a hairline and a deep shadow.
private struct SeleneDialogCard: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas

    func body(content: Content) -> some View {
        content
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

/// The same card with one pill per choice, left to right. The caller owns input: it moves `focus` with Left/Right
/// or hover and acts on `onChoose` (the choice's index); B and a click outside are the caller's cancel.
struct SeleneChoiceDialog: View {
    @Environment(\.seleneCanvas) private var canvas

    let title: String
    let message: String
    let choices: [String]
    @Binding var focus: Int
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .seleneFont(34, .semibold)
                .foregroundColor(SeleneTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .seleneFont(19)
                .foregroundColor(SeleneTheme.ink75)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, canvas.u(14))
            HStack(spacing: canvas.u(18)) {
                ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                    SelenePillButton(title: choice, focused: focus == index) { onChoose(index) }
                        .onHover { if $0 { focus = index } }
                        .accessibilityLabel(choice)
                }
            }
            .padding(.top, canvas.u(34))
        }
        .modifier(SeleneDialogCard())
    }
}
