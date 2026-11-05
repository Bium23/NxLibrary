import AppKit
import NXLibraryCore

/// Mods: a game's RomFS mods in its data folder (`~/Library/Application Support/nxnative/<title ID>/mods`), the
/// order and on/off state NX Library keeps for them, and the overlay line the game's launcher reads. Changes go
/// through `ModStore`, only while the game is not running.
extension AppViewModel {
    /// Nil when the game's app has no valid title ID.
    func modStore(for game: PortedGame) -> ModStore? {
        guard let titleID = CheatLocator.titleID(appURL: game.url, fallback: game.titleId) else { return nil }
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return ModStore(supportFolder: support.appendingPathComponent("nxnative/\(titleID)"),
                        recordsFile: support.appendingPathComponent("NXLibrary/mods/\(titleID).json"),
                        titleID: titleID,
                        canWrite: { RunningGameMonitor.runningApplication(for: game) == nil },
                        trash: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) })
    }

    func modsRowValue(for game: PortedGame) -> String {
        guard let mods = modStore(for: game)?.mods() else { return "None" }
        return ModStore.rowValue(on: mods.filter(\.isOn).count, total: mods.count)
    }

    /// Runs a change; nil when it worked, otherwise the sentence to show.
    func performModChange(_ change: () throws -> Void) -> String? {
        do {
            try change()
            return nil
        } catch let error as ModStoreError {
            return Self.modMessage(error)
        } catch {
            return "The mods could not be saved: \(error.localizedDescription)"
        }
    }

    nonisolated static func modMessage(_ error: ModStoreError) -> String {
        switch error {
        case .notAllowed: return "Quit the game to change its mods."
        case .notAMod(let name): return "\(name) isn't a mod: it needs a romfs folder."
        case .colonInName(let name): return "Rename the folder \(name): its name can't contain ':'."
        case .overlayTooLong: return "Too many mods are on for one game. Turn one off first."
        case .writeFailed(let reason): return "The mods could not be saved: \(reason)"
        }
    }
}
