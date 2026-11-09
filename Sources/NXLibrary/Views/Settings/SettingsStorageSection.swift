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

            SettingsSubheading(L10n.text("By game"))
            Text(L10n.text("Largest build caches first. Sizes describe file contents; the space recovered can differ. Shared folders count once in totals."))
                .seleneFont(15).foregroundColor(SeleneTheme.ink60)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let snapshot = viewModel.storageSnapshot {
                if snapshot.games.isEmpty {
                    Text(L10n.text("Add a game to see its storage here.")).seleneFont(15).foregroundColor(SeleneTheme.ink60)
                }
                ForEach(snapshot.games) { game in
                    SeleneButtonRow(game.name, id: game.rowID,
                                    subtitle: gameSummary(game), verbatimTitle: true,
                                    buttonTitle: "Delete cache") {
                        confirmCacheCleanup(game)
                    }
                    .disabled(!viewModel.canCleanStorage || !game.canDeleteCache)
                }
            }

            SettingsSubheading(L10n.text("All games"))

            SeleneButtonRow("Build caches",
                            subtitle: viewModel.isBuilding
                                ? "Available after the active build finishes or is cancelled."
                                : "Extracted build caches for every library game. Apps, sources and saves are untouched.",
                            info: "Intermediate files created during shader translation and staging in the app-owned workspace. Deleting them frees disk space; your built games and saves will not be touched.",
                            buttonTitle: "Delete all") {
                confirmCleanup(.caches)
            }
            .disabled(!viewModel.canCleanStorage || (viewModel.storageUsage?.cacheBytes ?? 0) == 0)

            SeleneButtonRow("Logs",
                            subtitle: "Build and launch logs. Apps, sources and saves are untouched.",
                            buttonTitle: "Delete") {
                confirmCleanup(.logs)
            }
            .disabled(!viewModel.canCleanStorage)

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

    private func sizeText(_ size: StorageSize, missing: String) -> String {
        switch size {
        case .bytes(let bytes): return seleneBytes(bytes)
        case .missing: return missing
        case .unavailable: return L10n.text("Unavailable")
        }
    }

    private func gameSummary(_ game: GameStorageUsage) -> String {
        var text = L10n.format("App: %@ · Cache: %@ · Logs: %@", [String(describing: (sizeText(game.app, missing: L10n.text("Not found")))), String(describing: (sizeText(game.cache, missing: "None"))), String(describing: (sizeText(game.logs, missing: "None")))])
        if !game.sharedCacheWith.isEmpty {
            text += L10n.format("\nCache shared with %@.", [String(describing: (game.sharedCacheWith.joined(separator: ", ")))])
        }
        return text
    }

    private func confirmCacheCleanup(_ usage: GameStorageUsage) {
        guard viewModel.canCleanStorage, usage.canDeleteCache,
              let game = viewModel.libraryGames.first(where: { $0.id == usage.id }) else { return }
        var message = L10n.format("Delete %@ of build cache for %@? This permanently removes extracted and compiled build files. The next rebuild may take longer. The game app, original game files, saves and logs are kept.", [String(describing: (seleneBytes(usage.cache.knownBytes ?? 0))), String(describing: (game.name))])
        if !usage.sharedCacheWith.isEmpty {
            message += L10n.format(" This cache is also used by %@; their next rebuilds may take longer too.", [String(describing: (usage.sharedCacheWith.joined(separator: ", ")))])
        }
        viewModel.showSettingsNotice(title: L10n.text("Delete this game's cache?"), message: message,
                                    actionTitle: L10n.text("Delete cache"), cancelTitle: L10n.text("Cancel")) {
            viewModel.deleteCaches(for: game)
        }
    }

    private func confirmCleanup(_ kind: CleanupKind) {
        let amount = kind == .logs
            ? seleneBytes(viewModel.storageUsage?.logsBytes ?? 0)
            : seleneBytes(viewModel.storageUsage?.cacheBytes ?? 0)
        let message = kind == .logs
            ? L10n.format("Remove %@ of logs for all games? Your games, sources and saves will be kept.", [String(describing: (amount))])
            : L10n.format("Permanently remove %@ of build caches for all games? Future rebuilds may take longer. Your games, original game files, saves and logs will be kept. Unavailable folders will be left alone.", [String(describing: (amount))])
        viewModel.showSettingsNotice(title: kind == .logs ? L10n.text("Delete logs?") : L10n.text("Delete build caches?"),
            message: message, actionTitle: L10n.text("Delete"), cancelTitle: L10n.text("Cancel")) {
            switch kind {
            case .caches: viewModel.deleteCaches()
            case .logs: viewModel.deleteLogs()
            }
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
        actions += (viewModel.storageSnapshot?.games ?? []).map { game in
            SettingsRowAction(id: game.rowID, title: game.name, rowID: game.rowID,
                              isEnabled: viewModel.canCleanStorage && game.canDeleteCache) {
                confirmCacheCleanup(game)
            }
        }
        actions += [
            .init(id: "deleteCaches", title: "Build caches", isEnabled: viewModel.canCleanStorage && (viewModel.storageUsage?.cacheBytes ?? 0) > 0) {
                confirmCleanup(.caches)
            },
            .init(id: "deleteLogs", title: "Logs", isEnabled: viewModel.canCleanStorage) {
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
        ]
        onActions(actions)
    }
}
