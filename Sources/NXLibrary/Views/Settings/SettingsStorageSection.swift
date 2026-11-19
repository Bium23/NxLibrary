import SwiftUI
import NXLibraryCore

struct SettingsStorageSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var artwork: ArtworkStore
    let onActions: ([SettingsRowAction]) -> Void

    @State private var metadataBytes: Int64 = 0
    @State private var artworkBytes: Int64 = 0

    var body: some View {
        VStack(spacing: 9) {
            SelenePanel(L10n.text("Storage")) {
                if let usage = viewModel.storageUsage {
                    usageRow(L10n.text("Library apps"), bytes: usage.libraryBytes)
                    usageRow("Build caches", bytes: usage.cacheBytes)
                    usageRow("Logs", bytes: usage.logsBytes)
                    if let free = viewModel.storageSnapshot?.freeBytes {
                        usageRow(L10n.text("Free on game apps volume"), bytes: free, positive: true)
                    } else {
                        Text(L10n.text("Game apps volume unavailable."))
                            .seleneFont(15).foregroundColor(SeleneTheme.ink60)
                    }
                    if viewModel.storageSnapshot?.hasUnavailableFiles == true {
                        Text(L10n.text("Some folders are unavailable. Totals include readable files only. Connect their drives or check folder access, then recalculate."))
                            .seleneFont(15).foregroundColor(SeleneTheme.ink60)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L10n.text("Calculating storage..."))
                            .seleneFont(15)
                            .foregroundColor(SeleneTheme.ink60)
                    }
                }
            }

            SeleneButtonRow("Storage usage",
                            subtitle: "Apps, build caches and logs for each game, including hidden games.",
                            buttonTitle: viewModel.isCalculatingStorage ? "Calculating…" : "Recalculate") {
                viewModel.refreshStorageUsage()
            }
            .disabled(viewModel.isCalculatingStorage || viewModel.isCleaningStorage)

            if viewModel.isCleaningStorage {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.text("Deleting files…")).seleneFont(15).foregroundColor(SeleneTheme.ink60)
                }
            } else if let message = viewModel.storageCleanupMessage {
                Text(message).seleneFont(15).foregroundColor(SeleneTheme.ink90)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(message)
            }

            SeleneButtonRow("Logs",
                            subtitle: "Build and launch logs. Apps, sources and saves are untouched.",
                            buttonTitle: "Delete") {
                confirmLogsCleanup()
            }
            .disabled(!viewModel.canCleanStorage)

            SeleneValueRow("Metadata cache",
                           subtitle: "Store and Wikipedia descriptions and links.",
                           value: seleneBytes(metadataBytes),
                           actionTitle: "Clear") {
                viewModel.clearMetadataCache()
                metadataBytes = viewModel.metadataCacheSize()
            }

            SeleneValueRow("Artwork cache",
                           subtitle: "Hero and cover art downloaded for this library.",
                           info: "High-resolution game box art and hero wallpapers cached locally from the Nintendo Store catalog.",
                           value: seleneBytes(artworkBytes),
                           actionTitle: "Clear") {
                artwork.clear()
                artworkBytes = artwork.cacheSize()
            }

            SeleneButtonRow("Save backups",
                            subtitle: "All games",
                            buttonTitle: "Open folder") {
                viewModel.showAllSaveBackups()
            }

        }
        .task {
            viewModel.refreshStorageUsage()
            metadataBytes = viewModel.metadataCacheSize()
            artworkBytes = artwork.cacheSize()
        }
        .onAppear(perform: publishActions)
        .onChange(of: viewModel.isBuilding) { building in
            publishActions()
            if !building { viewModel.refreshStorageUsage() }
        }
        .onChange(of: viewModel.isCleaningStorage) { _ in publishActions() }
        .onChange(of: viewModel.isCalculatingStorage) { _ in publishActions() }
        .onChange(of: viewModel.isUpdatingApp) { _ in publishActions() }
        .onChange(of: viewModel.storageSnapshot) { _ in publishActions() }
        .onChange(of: viewModel.libraryGames) { _ in viewModel.refreshStorageUsage() }
        .onChange(of: viewModel.libraryFolder) { _ in viewModel.refreshStorageUsage() }
    }

    private func confirmLogsCleanup() {
        let amount = seleneBytes(viewModel.storageUsage?.logsBytes ?? 0)
        let message = L10n.format("Remove %@ of logs for all games? Your games, sources and saves will be kept.", [String(describing: (amount))])
        viewModel.showSettingsNotice(title: L10n.text("Delete logs?"),
            message: message, actionTitle: L10n.text("Delete"), cancelTitle: L10n.text("Cancel")) {
            viewModel.deleteLogs()
        }
    }

    private func usageRow(_ title: String, bytes: Int64, positive: Bool = false) -> some View {
        HStack {
            Text(L10n.text(title))
                .seleneFont(15)
                .foregroundColor(SeleneTheme.ink90)
            Spacer()
            Text(seleneBytes(bytes))
                .seleneFont(15, .semibold, design: .monospaced)
                .foregroundColor(positive ? SeleneTheme.success : SeleneTheme.ink)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(SeleneTheme.glass.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func publishActions() {
        var actions: [SettingsRowAction] = [
            .init(id: "recalc", title: "Storage usage", isEnabled: !viewModel.isCalculatingStorage && !viewModel.isCleaningStorage) {
                viewModel.refreshStorageUsage()
            }
        ]
        actions += [
            .init(id: "deleteLogs", title: "Logs", isEnabled: viewModel.canCleanStorage) {
                confirmLogsCleanup()
            },
            .init(id: "metadataClear", title: "Metadata cache") {
                viewModel.clearMetadataCache()
                metadataBytes = viewModel.metadataCacheSize()
            },
            .init(id: "artworkClear", title: "Artwork cache") {
                artwork.clear()
                artworkBytes = artwork.cacheSize()
            },
            .init(id: "backups", title: "Save backups") {
                viewModel.showAllSaveBackups()
            }
        ]
        onActions(actions)
    }
}
