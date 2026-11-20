import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

/// Settings → Storage: measuring the library's space and asking to delete caches and logs (the deletion itself, which writes the shown state, stays in the type).
extension AppViewModel {
    func refreshStorageUsage() {
        guard !isCleaningStorage else { return }
        guard !isCalculatingStorage else { storageRefreshRequested = true; return }
        isCalculatingStorage = true
        let manager = storageManager
        let games = libraryGames
        let folder = gameAppsFolder
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let snapshot = manager.snapshot(games: games, applicationsFolder: folder)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCalculatingStorage = false
                if self.storageRefreshRequested || self.libraryGames != games || self.gameAppsFolder != folder {
                    self.storageRefreshRequested = false
                    self.refreshStorageUsage()
                } else {
                    self.storageSnapshot = snapshot
                }
            }
        }
    }

    func deleteCaches(for selected: PortedGame? = nil) {
        guard canCleanStorage else {
            showSettingsNotice(title: L10n.text("Cleanup unavailable"),
                               message: L10n.text("Wait for the current build, storage operation or app update to finish."))
            return
        }
        if let selected {
            guard let current = libraryGames.first(where: { $0.id == selected.id }),
                  current.buildCachePath == selected.buildCachePath,
                  current.workspacePath == selected.workspacePath else {
                showSettingsNotice(title: L10n.text("Cache changed"), message: L10n.text("Recalculate storage and choose the game again. Nothing was deleted."))
                refreshStorageUsage()
                return
            }
            cleanStorage(games: [current], caches: true)
        } else {
            cleanStorage(games: libraryGames, caches: true)
        }
    }

    func deleteLogs() {
        guard canCleanStorage else {
            showSettingsNotice(title: L10n.text("Cleanup unavailable"),
                               message: L10n.text("Wait for the current build, storage operation or app update to finish."))
            return
        }
        cleanStorage(games: libraryGames, caches: false)
    }
}
