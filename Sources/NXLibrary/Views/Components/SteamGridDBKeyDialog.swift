import SwiftUI
import AppKit
import NXLibraryCore

/// Adds the player's SteamGridDB API key: pasted, checked with SteamGridDB, then kept on this Mac. Shown from
/// Settings → Look and from Change artwork. Return saves, Esc cancels; on a controller A chooses the focused pill,
/// Left/Right move between them and B cancels. The owner stops its own input while the dialog is open.
struct SteamGridDBKeyDialog: View {
    @ObservedObject var viewModel: AppViewModel
    /// Where the owner's screen posts controller actions.
    let gamepad: Notification.Name
    /// True when a key was saved.
    let onClose: (Bool) -> Void

    @State private var draft = ""
    @State private var message: String?
    @State private var checking = false
    @State private var focus: SeleneConfirmButton = .confirm
    @FocusState private var fieldFocused: Bool
    @Environment(\.seleneCanvas) private var canvas

    var body: some View {
        ZStack {
            SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { close(saved: false) }
            SeleneConfirmDialog(title: "SteamGridDB key",
                                message: "Paste the API key from Preferences → API in your SteamGridDB profile. It stays on this Mac.",
                                confirmTitle: checking ? "Checking…" : "Save",
                                confirmEnabled: !checking && SteamGridDBKey.normalized(draft) != nil,
                                focus: $focus, onCancel: { close(saved: false) }, onConfirm: save) {
                VStack(alignment: .leading, spacing: canvas.u(12)) {
                    TextField("API key", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: max(13, canvas.u(17)), design: .monospaced))
                        .focused($fieldFocused)
                        .onSubmit(save)
                        .onExitCommand { close(saved: false) }
                        .disabled(checking)
                    HStack(spacing: canvas.u(6)) {
                        Text(message ?? "Free with a SteamGridDB account.")
                            .foregroundColor(message == nil ? SeleneTheme.ink60 : SeleneTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("Get a key") { NSWorkspace.shared.open(SteamGridDBArt.keyPage) }
                            .buttonStyle(.plain)
                            .foregroundColor(SeleneTheme.focus)
                    }
                    .seleneFont(14)
                }
                .seleneFont(17)
                .foregroundColor(SeleneTheme.ink)
                .padding(canvas.u(16))
                .background(RoundedRectangle(cornerRadius: canvas.u(12)).fill(SeleneTheme.glassLight))
                .padding(.top, canvas.u(24))
                .onAppear { fieldFocused = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: gamepad)) { note in
            guard let action = note.object as? GamepadAction else { return }
            switch action {
            case .navigateLeft: focus = .cancel
            case .navigateRight: focus = .confirm
            case .confirm: focus == .cancel ? close(saved: false) : save()
            case .cancel: close(saved: false)
            default: break
            }
        }
    }

    private func close(saved: Bool) {
        guard !checking else { return }
        if !saved { SoundEffectService.shared.play(.focus) }
        onClose(saved)
    }

    private func save() {
        guard !checking, SteamGridDBKey.normalized(draft) != nil else {
            message = SteamGridDBError.invalidKey.localizedDescription
            SoundEffectService.shared.play(.error)
            return
        }
        checking = true
        message = nil
        let text = draft
        Task { @MainActor in
            let problem = await viewModel.saveSteamGridDBKey(text)
            checking = false
            if let problem {
                message = problem
                SoundEffectService.shared.play(.error)
            } else {
                SoundEffectService.shared.play(.click)
                close(saved: true)
            }
        }
    }
}
