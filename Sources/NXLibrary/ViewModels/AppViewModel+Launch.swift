import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

/// Launching a Switch game: the launch screen, its checks and watching the launch.
extension AppViewModel {
    func launchGame(_ game: PortedGame) {
        // One launch at a time: the launch screen covers the library, and input reaching it changes nothing.
        guard launchingGameId == nil, launchOverlay == nil else { return }
        // A running game is brought forward, never started a second time.
        if let running = RunningGameMonitor.runningApplication(for: game) {
            RunningGameMonitor.activate(running)
            return
        }
        guard savesPermitPlay(game) else { return }
        // Installing a waiting build can itself start an icon update: check after installation too.
        let game = installingPendingBuild(of: game)
        // The app is being signed again with a new icon: starting it now could read a half-written bundle.
        guard !appIcon.appIconsInFlight.contains(game.id) else {
            appIcon.waitForAppIconBeforeLaunching(game)
            return
        }
        if !FileManager.default.fileExists(atPath: game.url.path),
           game.isPlayableLocally || game.status == .appMissing {
            let reason = GameUnavailableReason.appMissing
            lastError = reason.title + ". " + reason.detail
            alertMessage = lastError
            updateStoredStatus(.appMissing, for: game)
            SoundEffectService.shared.play(.error)
            return
        }
        guard game.isPlayableLocally else {
            let reason = GameResourceState.unavailableReason(for: game)
            let message = reason.map { $0.title + ". " + $0.detail }
                ?? L10n.text("This game is not built yet. Build it first.")
            lastError = message
            alertMessage = message
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: message))
            return
        }
        guard FileManager.default.fileExists(atPath: game.url.path) else {
            let reason = GameUnavailableReason.appMissing
            lastError = reason.title + ". " + reason.detail
            alertMessage = lastError
            updateStoredStatus(.appMissing, for: game)
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: lastError!))
            return
        }
        guard let titleId = game.titleId, !titleId.isEmpty else {
            lastError = NXLibraryError.missingTitleId.localizedDescription
            alertMessage = lastError
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: lastError!))
            return
        }

        guard let saveLaunchToken = saveGate.begin(titleID: titleId) else {
            alertMessage = SaveFailure.busy.localizedDescription
            return
        }
        launchingGameId = game.id
        launchOverlay = LaunchOverlayState(game: .nxnative(game))
        SoundEffectService.shared.play(.launch)

        // A saved-choices build reads the game's own store; only an older build takes env.txt and the environment.
        let gameSettings = runtimeSettings.gameSettings(for: game)
        let config = GameRuntimeConfig.load(for: game)
        do {
            if let gameSettings {
                try gameSettings.migrate()
            } else {
                try launchService.writeEnvironment(settings: config, titleId: titleId)
            }
        } catch {
            saveGate.end(titleID: titleId, token: saveLaunchToken)
            launchingGameId = nil
            launchOverlay = nil
            lastError = error.localizedDescription
            alertMessage = lastError
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error,
                                 message: L10n.format("Could not write the runtime environment: %@", [String(describing: error.localizedDescription)])))
            return
        }

        if let choice = settingsStore?.settings.cloudSaves, let domain = game.effectiveBundleId {
            do {
                try cloudSavesPreferences.applyBeforeLaunch(choice, domain: domain)
            } catch {
                logs.append(LogEntry(level: .warning, message: L10n.format("Cloud saves: %@", [String(describing: error.localizedDescription)])))
                showSettingsNotice(title: L10n.text("Cloud unavailable"),
                                   message: L10n.text("Cloud sync could not be updated for this launch. Check Games → Cloud saves."))
            }
        }

        // Play can come straight from the row. Reconcile removed mod folders before the game reads its overlay.
        if let store = modStore(for: game) { _ = performModChange { try store.sync() } }

        launchService.launch(appURL: game.url,
                             environment: gameSettings == nil ? config.toEnvironmentDict() : [:]) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.saveGate.end(titleID: titleId, token: saveLaunchToken)
                if success {
                    self.lastError = nil
                    self.playSessionStore?.start(for: game)
                    self.logs.append(LogEntry(level: .success, message: L10n.format("Launched game: %@", [String(describing: game.name)])))
                    self.watchLaunch(of: game)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if self.launchingGameId == game.id { self.launchingGameId = nil }
                    }
                } else {
                    let message = error ?? NXLibraryError.launchFailed(game.name).localizedDescription
                    self.launchingGameId = nil
                    self.launchOverlay = nil
                    self.lastError = message
                    self.alertMessage = message
                    SoundEffectService.shared.play(.error)
                    self.logs.append(LogEntry(level: .error, message: message))
                }
            }
        }
    }

    /// Marks the launch screen ready once the game shows a window, or after the probe times out.
    private func watchLaunch(of game: PortedGame) {
        launchProbeTask?.cancel()
        guard let bundleID = game.effectiveBundleId else {
            launchOverlay?.isReady = true
            return
        }
        launchProbeTask = Task { [weak self] in
            let visible = await LaunchReadinessProbe().waitUntilVisible(bundleID: bundleID)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.launchOverlay?.game.id == game.id else { return }
                if visible {
                    SoundEffectService.shared.play(.gameReady)
                } else {
                    self.logs.append(LogEntry(level: .warning,
                                              message: L10n.format("%@ showed no window within 60 s; launch screen closed.", [String(describing: game.name)])))
                }
                self.launchOverlay?.isReady = true
            }
        }
    }

    /// Called by the launch screen after its fade out.
    func dismissLaunchOverlay() {
        launchProbeTask?.cancel()
        launchProbeTask = nil
        launchOverlay = nil
    }
}
