import SwiftUI
import NXLibraryCore

struct SettingsStorageSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var artwork: ArtworkStore
    let onActions: ([SettingsRowAction]) -> Void
    let onOpenConsole: () -> Void

    @State private var backupGameID: UUID?
    @State private var cleanupToConfirm: CleanupKind?
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
                cleanupToConfirm = .caches
            }

            SeleneButtonRow("Logs",
                            subtitle: "Build and launch logs. Apps, sources and saves are untouched.",
                            buttonTitle: "Delete") {
                cleanupToConfirm = .logs
            }

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

            SeleneRow("Save backup",
                      subtitle: "Export one game's save folder as a zip archive.") {
                HStack(spacing: 10) {
                    Picker("", selection: $backupGameID) {
                        Text("Select a game").tag(nil as UUID?)
                        ForEach(viewModel.libraryGames) { game in
                            Text(game.name).tag(game.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)

                    Button("Back Up...") {
                        if let id = backupGameID,
                           let game = viewModel.libraryGames.first(where: { $0.id == id }) {
                            viewModel.backupSave(for: game)
                        }
                    }
                    .buttonStyle(.plain)
                    .seleneFont(14, .semibold)
                    .foregroundColor(SeleneTheme.glyph)
                    .disabled(backupGameID == nil)
                }
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
            if backupGameID == nil { backupGameID = viewModel.libraryGames.first?.id }
        }
        .onAppear(perform: publishActions)
        .confirmationDialog(cleanupTitle, isPresented: cleanupBinding, titleVisibility: .visible) {
            Button(cleanupButton, role: .destructive) {
                switch cleanupToConfirm {
                case .caches: viewModel.deleteCaches()
                case .logs: viewModel.deleteLogs()
                case nil: break
                }
                cleanupToConfirm = nil
            }
            Button("Cancel", role: .cancel) { cleanupToConfirm = nil }
        } message: {
            Text(cleanupMessage)
        }
    }

    private var cleanupBinding: Binding<Bool> {
        Binding(
            get: { cleanupToConfirm != nil },
            set: { if !$0 { cleanupToConfirm = nil } }
        )
    }

    private var cleanupTitle: String {
        cleanupToConfirm == .logs ? "Delete build and runtime logs?" : "Delete build caches?"
    }

    private var cleanupButton: String {
        cleanupToConfirm == .logs ? "Delete Logs" : "Delete Caches"
    }

    private var cleanupMessage: String {
        let amount = cleanupToConfirm == .logs
            ? seleneBytes(viewModel.storageUsage?.logsBytes ?? 0)
            : seleneBytes(viewModel.storageUsage?.cacheBytes ?? 0)
        if cleanupToConfirm == .logs {
            return "This removes \(amount) of logs for every library game. It does not touch saves, apps or sources."
        }
        return "This removes \(amount) of extracted build caches for every library game. A future build will extract the sources again. Apps, sources and saves are not deleted."
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
                cleanupToConfirm = .caches
            },
            .init(id: "deleteLogs", title: "Logs", isEnabled: !viewModel.isBuilding) {
                cleanupToConfirm = .logs
            },
            .init(id: "metadataClear", title: "Metadata cache") {
                viewModel.clearMetadataCache()
                metadataBytes = viewModel.metadataCacheSize()
            },
            .init(id: "artworkClear", title: "Artwork cache") {
                artwork.clear()
                artworkBytes = artwork.cacheSize()
            },
            .init(id: "backup", title: "Save backup", isEnabled: backupGameID != nil) {
                if let id = backupGameID,
                   let game = viewModel.libraryGames.first(where: { $0.id == id }) {
                    viewModel.backupSave(for: game)
                }
            },
            .init(id: "console", title: "Console") {
                onOpenConsole()
            }
        ])
    }
}
