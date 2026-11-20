import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

/// A game's files: removing its sources, deleting it, the file pickers and its porting log.
extension AppViewModel {
    /// A human-readable summary for the destructive source-removal confirmation.
    func sourceRemovalSummary(for game: PortedGame) -> String {
        let fm = FileManager.default
        let existingSources = game.sources.filter {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: $0.url.path, isDirectory: &isDir) && !isDir.boolValue
        }
        let sourceBytes = existingSources.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let workspaceBytes: Int64
        if let path = game.workspacePath {
            let workspace = URL(fileURLWithPath: path).standardizedFileURL
            workspaceBytes = BuildScratch.isManaged(workspace, core: core)
                ? directorySize(workspace) : 0
        } else {
            workspaceBytes = 0
        }

        var parts: [String] = []
        if !existingSources.isEmpty {
            parts.append(L10n.count("%lld original source files (%@)", existingSources.count, arguments: [Self.formatBytes(sourceBytes)]))
        }
        if workspaceBytes > 0 {
            parts.append(L10n.format("Build cache (%@)", [Self.formatBytes(workspaceBytes)]))
        }
        let target = parts.isEmpty ? L10n.text("Remaining build data") : parts.joined(separator: ", ")
        return L10n.format("This permanently deletes: %@. The installed app, saves and logs stay. Rebuilds will be disabled until you attach the sources again. This cannot be undone.", [target])
    }

    func removeSources(for game: PortedGame) {
        guard !isBuilding else {
            alertMessage = L10n.text("Wait for the current build to finish before removing sources.")
            return
        }
        let fm = FileManager.default
        let current: CatalogDocument
        do { current = try catalogRepository.load() }
        catch { reportCatalogFailure(error); return }
        guard current.nxnativeGames.contains(where: { $0.id == game.id }) else {
            alertMessage = L10n.format("Could not load the library entry for %@.", [game.name])
            return
        }

        let appPath = game.url.standardizedFileURL.path
        let otherGames = current.nxnativeGames.filter { $0.id != game.id }
        var removedCount = 0
        var removedBytes: Int64 = 0
        var failures: [String] = []

        for source in game.sources {
            let url = source.url.standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                failures.append(L10n.format("%@ is a folder", [url.lastPathComponent]))
                continue
            }
            if url.path.hasPrefix(appPath + "/") {
                failures.append(L10n.format("%@ is inside the app", [url.lastPathComponent]))
                continue
            }
            let shared = otherGames.contains { other in
                other.sources.contains { $0.url.standardizedFileURL == url }
            }
            if shared {
                failures.append(L10n.format("%@ is also used by another library entry", [url.lastPathComponent]))
                continue
            }
            do {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                    .map(Int64.init) ?? source.sizeBytes
                try fm.removeItem(at: url)
                removedCount += 1
                removedBytes += size
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        var removedWorkspace = false
        if let path = game.workspacePath {
            let workspace = URL(fileURLWithPath: path).standardizedFileURL
            if BuildScratch.isManaged(workspace, core: core),
               fm.fileExists(atPath: workspace.path) {
                do {
                    try fm.removeItem(at: workspace)
                    removedWorkspace = true
                } catch {
                    failures.append(L10n.format("Build cache: %@", [error.localizedDescription]))
                }
            }
        }

        var updated = current.nxnativeGames.first { $0.id == game.id }!
        updated.sources = updated.sources.filter { source in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: source.url.path, isDirectory: &isDir)
                && !isDir.boolValue
        }
        if removedWorkspace || updated.workspacePath.map({
            !fm.fileExists(atPath: URL(fileURLWithPath: $0).path)
        }) == true {
            updated.workspacePath = nil
            updated.buildCachePath = nil
        }
        if updated.sources.isEmpty {
            updated.status = .builtSourcesMissing
        }
        do {
            applyCatalog(try catalogRepository.updateNXNative(id: game.id) { stored in
                stored.sources = updated.sources
                stored.workspacePath = updated.workspacePath
                stored.buildCachePath = updated.buildCachePath
                stored.status = updated.status
            })
        } catch {
            alertMessage = L10n.format("The sources were removed, but the library could not be saved: %@", [error.localizedDescription])
            logs.append(LogEntry(level: .error, message: alertMessage!))
            return
        }
        let removed = L10n.count("Removed %lld source files (%@).", removedCount, arguments: [Self.formatBytes(removedBytes)])
            + (removedWorkspace ? " " + L10n.text("The build cache was also removed.") : "")
        if failures.isEmpty {
            logs.append(LogEntry(level: .success,
                                 message: L10n.format("%@ The installed app and saves were kept.", [String(describing: removed)])))
            alertMessage = L10n.format("%@ The installed app and saves were kept. Rebuilds stay disabled until you attach the sources again.", [removed])
        } else {
            let detail = failures.joined(separator: "; ")
            logs.append(LogEntry(level: .warning,
                                 message: L10n.format("%@ Some items were kept: %@", [String(describing: removed), String(describing: detail)])))
            alertMessage = L10n.format("%@ Some items were kept: %@", [removed, detail])
        }
    }

    private func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                .map(Int64.init) ?? 0
        }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    static func formatBytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(L10n.context.formatLocale))
    }

    func deletePortedGame(_ game: PortedGame) {
        do {
            let deleteBundle = game.canDeleteAppBundle()
            if deleteBundle, FileManager.default.fileExists(atPath: game.url.path) {
                try FileManager.default.removeItem(at: game.url)
            }

            // Remove only the app-owned staged workspace. A folder-mode game's
            // workspace is the user's source folder and must never be touched.
            var removedWorkspace = false
            if let path = game.workspacePath {
                let workspace = URL(fileURLWithPath: path).standardizedFileURL
                if BuildScratch.isManaged(workspace, core: core),
                   FileManager.default.fileExists(atPath: workspace.path) {
                    try? FileManager.default.removeItem(at: workspace)
                    removedWorkspace = !FileManager.default.fileExists(atPath: workspace.path)
                }
            }

            applyCatalog(try catalogRepository.updateNXNativeGames { games in
                games.removeAll { $0.id == game.id }
            })
            if deleteBundle {
                logs.append(LogEntry(level: .warning,
                    message: L10n.format("Game app deleted: %@%@", [String(describing: game.name), String(describing: removedWorkspace ? "; staged workspace removed" : "")])))
            } else {
                logs.append(LogEntry(level: .warning,
                    message: L10n.format("Removed %@ from the library; its source folders were left in place.", [String(describing: game.name)])))
            }
        } catch {
            let message = L10n.format("Failed to delete game: %@", [String(describing: error.localizedDescription)])
            alertMessage = message
            logs.append(LogEntry(level: .error, message: message))
        }
    }

    // MARK: - File Pickers

    func selectRyujinxFolder() {
        guard !isBuilding, !isUpdatingApp else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Ryujinx Folder"
        panel.message = "Select your Ryujinx folder to automatically locate prod.keys."

        if panel.runModal() == .OK, let url = panel.url {
            setup.detectEnvironment(customRyujinxDir: url.path)
        }
    }

    func logURL(for game: PortedGame) -> URL? {
        if let path = game.lastBuild?.logPath, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        guard let titleId = game.titleId, !titleId.isEmpty else { return nil }
        return launchService.logURL(for: titleId)
    }

    func revealLog(for game: PortedGame) {
        guard let url = logURL(for: game) else {
            logs.append(LogEntry(level: .warning, message: L10n.format("No log path is known for %@.", [String(describing: game.name)])))
            return
        }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
            logs.append(LogEntry(level: .info,
                                 message: L10n.format("No log yet for %@; opened the log folder.", [String(describing: game.name)])))
        }
    }
}
