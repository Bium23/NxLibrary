import SwiftUI
import AppKit
import NXLibraryCore

/// Only the player's Save action sends their own application credentials to Twitch/IGDB.
struct IGDBCredentialsDialog: View {
    @ObservedObject var model: IGDBSettings
    let onClose: () -> Void
    @Environment(\.seleneCanvas) private var canvas
    @State private var clientID = ""
    @State private var secret = ""
    @State private var message: String?
    @State private var checking = false
    @State private var focus: SeleneConfirmButton = .confirm
    @State private var task: Task<Void, Never>?
    private enum Field: Hashable { case client, secret }
    @FocusState private var field: Field?

    var body: some View {
        ZStack {
            SeleneTheme.scrim45.ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: close)
            SeleneConfirmDialog(title: "IGDB", message: L10n.text("Use your Twitch application credentials for critic scores. They stay on this Mac and are sent only to Twitch and IGDB."),
                                confirmTitle: checking ? L10n.text("Checking…") : L10n.text("Check and save"),
                                confirmEnabled: !checking && draft != nil,
                                focus: $focus, onCancel: close, onConfirm: save) {
                VStack(alignment: .leading, spacing: canvas.u(14)) {
                    setupSteps
                    VStack(alignment: .leading, spacing: canvas.u(6)) {
                        Text(L10n.text("Client ID")).seleneFont(14).foregroundColor(SeleneTheme.ink60)
                        TextField(L10n.text("Client ID"), text: $clientID)
                            .focused($field, equals: .client).onSubmit { field = .secret }
                    }
                    .disabled(checking)
                    VStack(alignment: .leading, spacing: canvas.u(6)) {
                        Text(L10n.text("Client Secret")).seleneFont(14).foregroundColor(SeleneTheme.ink60)
                        SecureField(L10n.text("Client Secret"), text: $secret)
                            .focused($field, equals: .secret).onSubmit(save)
                    }
                    .disabled(checking)
                    if let message {
                        Text(message).seleneFont(14).foregroundColor(SeleneTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button(L10n.text("Developer portal")) {
                            NSWorkspace.shared.open(URL(string: "https://dev.twitch.tv/console/apps/create")!)
                        }
                        Spacer(minLength: 0)
                        Button(L10n.text("Setup guide")) {
                            NSWorkspace.shared.open(URL(string: "https://api-docs.igdb.com/#account-creation")!)
                        }
                    }
                    .buttonStyle(.plain).seleneFont(14).foregroundColor(SeleneTheme.focus)
                }
                .textFieldStyle(.plain)
                .font(.system(size: max(13, canvas.u(17)), design: .monospaced))
                .foregroundColor(SeleneTheme.ink)
                .padding(canvas.u(16))
                .background(RoundedRectangle(cornerRadius: canvas.u(12)).fill(SeleneTheme.glassLight))
                .padding(.top, canvas.u(24))
            }
        }
        .onAppear {
            if let current = model.credentials { clientID = current.clientID; secret = current.clientSecret }
            field = .client
        }
        .onDisappear { task?.cancel(); secret = "" }
        .onExitCommand(perform: close)
        .onReceive(NotificationCenter.default.publisher(for: .nxSettingsGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            switch action {
            case .navigateUp: field = .client
            case .navigateDown: field = .secret
            case .navigateLeft: focus = .cancel
            case .navigateRight: focus = .confirm
            case .confirm: focus == .cancel ? close() : save()
            case .cancel: close()
            default: break
            }
        }
    }
    private var setupSteps: some View {
        let steps = [
            L10n.text("Open the developer portal: Applications → Register Your Application."),
            L10n.text("Choose a unique name. OAuth Redirect URLs: http://localhost → Add."),
            L10n.text("Category: Application Integration. Client Type: Confidential."),
            L10n.text("Create → Manage → New Secret."),
            L10n.text("Paste Client ID and Client Secret below, then Check and save.")
        ]
        return VStack(alignment: .leading, spacing: canvas.u(7)) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: canvas.u(9)) {
                    Text("\(index + 1).")
                        .foregroundColor(SeleneTheme.ink60)
                        .frame(width: canvas.u(18), alignment: .leading)
                    Text(text).foregroundColor(SeleneTheme.ink90)
                }
            }
            Text(L10n.text("Twitch requires a verified email and two-factor authentication."))
                .foregroundColor(SeleneTheme.ink60)
                .padding(.top, canvas.u(3))
        }
        .seleneFont(14)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, canvas.u(6))
    }
    private var draft: IGDBCredentials? { IGDBCredentials(clientID: clientID, clientSecret: secret) }
    private func close() { task?.cancel(); secret = ""; onClose() }
    private func save() {
        guard !checking else { return }
        guard let credentials = draft else { message = IGDBError.invalidCredentials.localizedDescription; return }
        checking = true; message = nil
        task = Task { @MainActor in
            do {
                try await model.save(credentials)
                guard !Task.isCancelled else { return }
                SoundEffectService.shared.play(.click)
                close()
            } catch {
                guard !Task.isCancelled else { return }
                checking = false
                message = (error as? IGDBError ?? .unreachable).localizedDescription
                SoundEffectService.shared.play(.error)
            }
        }
    }
}
