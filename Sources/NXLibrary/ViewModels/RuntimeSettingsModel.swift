import Foundation
import NXLibraryCore
import ArcanePorting

/// A built game's saved choices for its next launch, as Game options and More settings show them: reading, writing,
/// restoring the new-game defaults and which settings the build supports. It keeps no state: the game's files are the
/// truth (`NXNativeGameSettings`, or env.txt for a build from before saved choices). It reaches the rest of Arcane
/// only through `app`: the log, the notice and the new-game defaults.
final class RuntimeSettingsModel {
    /// The coordinator: log, notices and the player's settings.
    unowned let app: AppViewModel

    init(app: AppViewModel) {
        self.app = app
    }

    func loadRuntimeConfig(for game: PortedGame) -> GameRuntimeConfig {
        gameSettings(for: game)?.runtimeConfig() ?? GameRuntimeConfig.load(for: game)
    }

    /// The game's saved-choices store, or nil for a build from before saved choices (env.txt).
    func gameSettings(for game: PortedGame) -> NXNativeGameSettings? {
        NXNativeGameSettings.forGame(game)
    }

    func settingsSnapshot(for game: PortedGame) -> GameSettingsSnapshot? {
        gameSettings(for: game)?.snapshot()
    }

    /// One saved choice; false (with a notice) when it could not be kept.
    @discardableResult func setGameSetting(_ env: String, to value: String, for game: PortedGame) -> Bool {
        guard let settings = gameSettings(for: game) else { return false }
        do {
            try settings.set(env, to: value)
            return true
        } catch {
            settingsNotSaved(game, error)
            return false
        }
    }

    /// Use new game defaults: every setting to the build's default, then Arcane's new-game defaults.
    func restoreGameDefaults(for game: PortedGame) {
        guard let settings = gameSettings(for: game) else { return }
        do {
            try settings.resetAll()
            let base = settings.runtimeConfig()
            try settings.apply(app.settingsStore?.settings.gameDefaults ?? GameRuntimeConfig(), changedFrom: base)
        } catch {
            settingsNotSaved(game, error)
        }
    }

    private func settingsNotSaved(_ game: PortedGame, _ error: Error) {
        app.logs.append(LogEntry(level: .error, message: L10n.format("Could not save settings for %@: %@", [String(describing: game.name), String(describing: error.localizedDescription)])))
        app.showSettingsNotice(title: L10n.text("Options not saved"), message: L10n.text("Your game options could not be saved. Try again."))
    }

    func supportsSetting(_ env: String, for game: PortedGame) -> Bool {
        LauncherSettingsReader.supports(env, for: game.url)
    }

    @discardableResult func saveRuntimeConfig(_ config: GameRuntimeConfig, for game: PortedGame) -> Bool {
        do {
            try config.save(for: game)
            app.logs.append(LogEntry(level: .success, message: L10n.format("Saved settings for %@", [String(describing: game.name)])))
            return true
        } catch {
            app.logs.append(LogEntry(level: .error, message: L10n.format("Could not save settings for %@: %@", [String(describing: game.name), String(describing: error.localizedDescription)])))
            app.showSettingsNotice(title: L10n.text("Options not saved"), message: L10n.text("Your game options could not be saved. Try again.")) { [weak self] in
                self?.saveRuntimeConfig(config, for: game)
            }
            return false
        }
    }
}
