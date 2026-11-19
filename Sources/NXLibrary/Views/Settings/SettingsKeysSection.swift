import SwiftUI
import NXLibraryCore

/// Porting → Keys: the private copy of prod.keys that new portings need.
struct SettingsKeysSection: View {
    @ObservedObject var viewModel: AppViewModel
    /// The imported keys (`SetupModel`), observed on their own.
    @ObservedObject var setup: SetupModel
    let onActions: ([SettingsRowAction]) -> Void

    @Environment(\.seleneFocusedRowID) private var focusedRowTitle
    private var configurationLocked: Bool { viewModel.isBuilding || viewModel.isUpdatingApp }

    var body: some View {
        VStack(spacing: 9) {
            SelenePanel(L10n.text("prod.keys"),
                        info: L10n.text("Nintendo Switch cryptographic keys required to decrypt game packages (NSP/XCI). Arcane stores a private copy with mode 0600 permissions; key values are never displayed or logged.")) {
                HStack(spacing: 8) {
                    Image(systemName: setup.isProdKeysValid ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .seleneFont(15, .bold)
                        .foregroundColor(setup.isProdKeysValid ? SeleneTheme.success : SeleneTheme.danger)
                    Text(setup.isProdKeysValid ? L10n.text("Keys imported") : L10n.text("No prod.keys imported"))
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.ink)
                    Spacer()
                    Text(setup.isProdKeysValid && !setup.prodKeysPath.isEmpty
                         ? setup.prodKeysPath : L10n.text("Choose your file once"))
                        .seleneFont(13, .regular, design: .monospaced)
                        .foregroundColor(SeleneTheme.ink60)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let summary = setup.keySummary {
                    Text(L10n.format("header_key present · %@ application key generations", [String(describing: (summary.applicationKeyGenerations.count))]))
                        .seleneFont(13, .regular, design: .monospaced)
                        .foregroundColor(SeleneTheme.success)
                }

                HStack(spacing: 14) {
                    Button(setup.isProdKeysValid ? L10n.text("Replace Key...") : L10n.text("Import Key...")) {
                        setup.selectProdKeysFile()
                    }
                    .buttonStyle(.plain)
                    .seleneFont(14, .semibold)
                    .foregroundColor(SeleneTheme.glyph)
                    .disabled(configurationLocked)
                    Button(L10n.text("Detect Ryujinx...")) { viewModel.selectRyujinxFolder() }
                        .buttonStyle(.plain)
                        .seleneFont(14, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                        .disabled(configurationLocked)
                    Spacer()
                }

                Text(L10n.text("The original file is untouched. The stored copy is mode 0600 and key values are never shown or logged."))
                    .seleneFont(13)
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .seleneRowFocus(focusedRowTitle == "prod.keys", radius: SeleneTheme.cardRadius)
        }
        .onAppear(perform: publishActions)
        .onChange(of: configurationLocked) { _ in publishActions() }
    }

    private func publishActions() {
        onActions([
            .init(id: "keys", title: "prod.keys", isEnabled: !configurationLocked) {
                setup.selectProdKeysFile()
            }
        ])
    }
}
