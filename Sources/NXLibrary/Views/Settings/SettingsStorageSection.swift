import SwiftUI
import NXLibraryCore

struct SettingsStorageSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var artwork: ArtworkStore
    let onActions: ([SettingsRowAction]) -> Void
    let onOpenConsole: () -> Void

    @State private var metadataBytes: Int64 = 0
    @State private var artworkBytes: Int64 = 0

    private enum CleanupKind: String, Identifiable {
        case caches, logs
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 9) {
            SelenePanel("Storage") {
                if let usage = viewModel.storageUsage {
                    usageRow("Library apps", bytes: usage.libraryBytes)
                    usageRow("Build caches", bytes: usage.cacheBytes)
                    usageRow("Logs", bytes: usage.logsBytes)
                    usageRow("Free on volume", bytes: usage.freeBytes, positive: true)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Calculating storage...")
                            .seleneFont(15)
                            .foregroundColor(SeleneTheme.ink60)
                    }
                }
            }

            SeleneButtonRow("Storage usage",
                            subtitle: "Recalculate apps, build caches, logs and free space.",
                            buttonTitle: "Recalculate") {
                viewModel.refreshStorageUsage()
            }

            SeleneButtonRow("Build caches",
                            subtitle: viewModel.isBuilding
                                ? "Available after the active build finishes or is cancelled."
                                : "Extracted build caches for every library game. Apps, sources and saves are untouched.",
                            info: "Intermediate files created during shader translation and staging in the app-owned workspace. Deleting them frees disk space; your built games and saves will not be touched.",
                            buttonTitle: "Delete") {
                confirmCleanup(.caches)
            }
            .disabled(viewModel.isBuilding)

            SeleneButtonRow("Logs",
                            subtitle: "Build and launch logs. Apps, sources and saves are untouched.",
                            buttonTitle: "Delete") {
                confirmCleanup(.logs)
            }
            .disabled(viewModel.isBuilding)

            SeleneValueRow("Metadata cache",
                           subtitle: "Nintendo Store descriptions and links.",
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

            SeleneButtonRow("Console",
                            subtitle: "Filter, search and copy build and launch logs.",
                            buttonTitle: "Open") {
                onOpenConsole()
            }
        }
        .task {
            viewModel.refreshStorageUsage()
            metadataBytes = viewModel.metadataCacheSize()
            artworkBytes = artwork.cacheSize()
        }
        .onAppear(perform: publishActions)
        .onChange(of: viewModel.isBuilding) { _ in publishActions() }
    }

    private func confirmCleanup(_ kind: CleanupKind) {
        let amount = kind == .logs
            ? seleneBytes(viewModel.storageUsage?.logsBytes ?? 0)
            : seleneBytes(viewModel.storageUsage?.cacheBytes ?? 0)
        let message = kind == .logs
            ? "Remove \(amount) of logs for all games? Your games, sources and saves will be kept."
            : "Remove \(amount) of build caches? Future portings will extract the sources again. Your games, sources and saves will be kept."
        viewModel.showSettingsNotice(title: kind == .logs ? "Delete logs?" : "Delete build caches?",
            message: message, actionTitle: "Delete", cancelTitle: "Cancel") {
            switch kind {
            case .caches: viewModel.deleteCaches()
            case .logs: viewModel.deleteLogs()
            }
        }
    }

    private func usageRow(_ title: String, bytes: Int64, positive: Bool = false) -> some View {
        HStack {
            Text(title)
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
        onActions([
            .init(id: "recalc", title: "Storage usage") {
                viewModel.refreshStorageUsage()
            },
            .init(id: "deleteCaches", title: "Build caches", isEnabled: !viewModel.isBuilding) {
                confirmCleanup(.caches)
            },
            .init(id: "deleteLogs", title: "Logs", isEnabled: !viewModel.isBuilding) {
                confirmCleanup(.logs)
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
            },
            .init(id: "console", title: "Console") {
                onOpenConsole()
            }
        ])
    }
}
