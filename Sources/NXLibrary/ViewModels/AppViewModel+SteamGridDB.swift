import Foundation
import NXLibraryCore

extension AppViewModel {
    /// Checks the key with SteamGridDB, then keeps it on this Mac. Nil when saved, else what to tell the player.
    @MainActor
    func saveSteamGridDBKey(_ text: String) async -> String? {
        guard let key = SteamGridDBKey.normalized(text) else { return SteamGridDBError.invalidKey.localizedDescription }
        if case .failure(let error) = await SteamGridDBArt.check(key: key) { return error.localizedDescription }
        do {
            try SteamGridDBKey().save(key)
        } catch {
            return error.localizedDescription
        }
        hasSteamGridDBKey = true
        logs.append(LogEntry(level: .info, message: L10n.text("SteamGridDB key saved; Change artwork searches SteamGridDB.")))
        return nil
    }

    func removeSteamGridDBKey() {
        do {
            try SteamGridDBKey().remove()
            hasSteamGridDBKey = false
        } catch {
            showSettingsNotice(title: L10n.text("Key not removed"), message: error.localizedDescription) { [weak self] in
                self?.removeSteamGridDBKey()
            }
        }
    }
}
