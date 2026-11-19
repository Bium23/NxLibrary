import SwiftUI
import NXLibraryCore

/// General, optional connections; moving them here leaves stored credentials and provider behaviour intact.
struct SettingsAPISection: View {
    @ObservedObject var viewModel: AppViewModel
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas
    @ObservedObject private var igdb = IGDBSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(8)) {
            Text(L10n.text("Connect optional services to enrich your library with ratings and artwork. Public sources remain available without API keys."))
                .seleneFont(16)
                .foregroundColor(SeleneTheme.ink60)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, canvas.u(8))

            SettingsSubheading(L10n.text("Ratings"))
            SeleneRow("IGDB", subtitle: igdb.message ?? (igdb.isConfigured
                      ? "IGDB connected · Wikidata is the fallback"
                      : "Optional critic scores with your own credentials")) {
                HStack(spacing: canvas.u(18)) {
                    Button(L10n.text(igdb.isConfigured ? "Edit credentials" : "Connect")) { igdb.isEditing = true }
                        .foregroundColor(SeleneTheme.glyph)
                    if igdb.isConfigured {
                        Button(L10n.text("Remove")) { Task { await igdb.remove() } }
                            .foregroundColor(SeleneTheme.ink60).disabled(igdb.isRemoving)
                    }
                }
                .buttonStyle(.plain).seleneFont(15, .semibold)
            }

            SettingsSubheading(L10n.text("Artwork"))
            SeleneButtonRow("SteamGridDB",
                            subtitle: viewModel.hasSteamGridDBKey
                                ? "Key saved · covers, backgrounds, logos and icons in Change artwork"
                                : "Add your free API key to find art in Change artwork",
                            buttonTitle: viewModel.hasSteamGridDBKey ? "Remove key" : "Add key") {
                steamGridDBAction()
            }
        }
        .onAppear(perform: publishActions)
        .onChange(of: igdb.revision) { publishActions() }
    }
    private func steamGridDBAction() {
        if viewModel.hasSteamGridDBKey { viewModel.removeSteamGridDBKey() }
        else { viewModel.isEditingSteamGridDBKey = true }
    }
    private func publishActions() {
        onActions([
            .init(id: "IGDB", title: "IGDB",
                  secondary: igdb.isConfigured ? (title: "Remove", activate: { Task { await igdb.remove() }; return }) : nil) {
                igdb.isEditing = true
            },
            .init(id: "SteamGridDB", title: "SteamGridDB") { steamGridDBAction() }
        ])
    }
}
