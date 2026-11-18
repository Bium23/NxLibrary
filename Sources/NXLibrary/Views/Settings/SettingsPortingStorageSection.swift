import SwiftUI
import NXLibraryCore

/// Porting → Storage: the build caches of each game and of all games, largest first.
struct SettingsPortingStorageSection: View {
    @ObservedObject var viewModel: AppViewModel
    let onActions: ([SettingsRowAction]) -> Void

    var body: some View {
        VStack(spacing: 9) {
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
                confirmAllCachesCleanup()
            }
            .disabled(!viewModel.canCleanStorage || (viewModel.storageUsage?.cacheBytes ?? 0) == 0)
        }
        .task { viewModel.refreshStorageUsage() }
        .onAppear(perform: publishActions)
        .onChange(of: viewModel.isBuilding) { building in
            publishActions()
            if !building { viewModel.refreshStorageUsage() }
        }
        .onChange(of: viewModel.isCleaningStorage) { _ in publishActions() }
        .onChange(of: viewModel.isUpdatingApp) { _ in publishActions() }
        .onChange(of: viewModel.storageSnapshot) { _ in publishActions() }
        .onChange(of: viewModel.storageUsage?.cacheBytes) { _ in publishActions() }
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

    private func confirmAllCachesCleanup() {
        let amount = seleneBytes(viewModel.storageUsage?.cacheBytes ?? 0)
        let message = L10n.format("Permanently remove %@ of build caches for all games? Future rebuilds may take longer. Your games, original game files, saves and logs will be kept. Unavailable folders will be left alone.", [String(describing: (amount))])
        viewModel.showSettingsNotice(title: L10n.text("Delete build caches?"), message: message,
                                    actionTitle: L10n.text("Delete"), cancelTitle: L10n.text("Cancel")) {
            viewModel.deleteCaches()
        }
    }

    private func publishActions() {
        var actions: [SettingsRowAction] = (viewModel.storageSnapshot?.games ?? []).map { game in
            SettingsRowAction(id: game.rowID, title: game.name, rowID: game.rowID,
                              isEnabled: viewModel.canCleanStorage && game.canDeleteCache) {
                confirmCacheCleanup(game)
            }
        }
        actions.append(.init(id: "deleteCaches", title: "Build caches",
                             isEnabled: viewModel.canCleanStorage && (viewModel.storageUsage?.cacheBytes ?? 0) > 0) {
            confirmAllCachesCleanup()
        })
        onActions(actions)
    }
}
