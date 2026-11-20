import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

/// Actions: changing a setting or the language, each row's action and Rebuild.
extension GameOptionsView {
    /// A setting row of a build with saved choices, with the value that applies now.
    func settingValue(_ row: GameOptionsRow) -> (LauncherSetting, String)? {
        guard let snapshot, let key = row.settingKey, let setting = snapshot.setting(key) else { return nil }
        return (setting, snapshot.value(key) ?? setting.defaultValue ?? "")
    }

    /// Changes a setting row of a build with saved choices: a switch flips, a value steps. A row env.txt sets
    /// does not change.
    private func changeSetting(_ row: GameOptionsRow, by delta: Int) {
        guard let (setting, value) = settingValue(row) else { return }
        guard !presentation.isFixed(row) else {
            SoundEffectService.shared.play(.error)
            return
        }
        SoundEffectService.shared.play(.click)
        let next: String
        if row.isToggle, setting.kind != "toggle" {
            // A two-option choice drawn as a switch (Display mode, Upscaling).
            next = value == row.onValue
                ? (setting.options?.first { $0.value != row.onValue }?.value ?? value)
                : row.onValue
        } else {
            next = GameSettingValues.stepped(setting, from: value, by: delta)
        }
        viewModel.runtimeSettings.setGameSetting(setting.env, to: next, for: current)
        snapshot = viewModel.runtimeSettings.settingsSnapshot(for: current)
    }

    /// Left/Right on a choice row: step backwards or forwards.
    func adjust(_ row: GameOptionsRow, by delta: Int) {
        if snapshot != nil, row.settingKey != nil {
            changeSetting(row, by: delta)
            return
        }
        SoundEffectService.shared.play(.click)
        switch row {
        case .consoleMode:
            config.isDockedMode.toggle()
        case .language:
            cycleLanguage(by: delta)
        case .rumbleStrength:
            config.rumbleGain = GameOptionsValues.steppedRumbleStrength(config.rumbleGain, by: delta)
        case .renderScale:
            config.renderScale = GameOptionsValues.steppedRenderScale(config.renderScale, by: delta)
        default:
            break
        }
    }

    private func cycleLanguage(by delta: Int) {
        let options = viewModel.availableLanguages
        guard !options.isEmpty else { return }
        let index = options.firstIndex { $0.code == config.language }
        let next = GameOptionsValues.steppedIndex(index, by: delta, count: options.count)
        config.language = options[next].code
    }

    /// The row's action. A on a choice row steps it forwards.
    func perform(_ row: GameOptionsRow) {
        if snapshot != nil, row.settingKey != nil {
            changeSetting(row, by: 1)
            return
        }
        switch row {
        case .play:
            guard presentation.canPlay else {
                SoundEffectService.shared.play(.error)
                return
            }
            SoundEffectService.shared.play(.click)
            onClose()
            viewModel.launchGame(current)
        case .move:
            SoundEffectService.shared.play(.click)
            onMove()
        case .favorite:
            SoundEffectService.shared.play(.click)
            viewModel.toggleFavorite(current)
        case .hidden:
            SoundEffectService.shared.play(.click)
            let hiding = !current.isHidden
            viewModel.toggleHidden(current)
            // Close only once the hidden flag is saved: a failed save leaves the game listed.
            let nowHidden = viewModel.libraryGames.first { $0.id == game.id }?.isHidden ?? false
            if hiding && nowHidden { onClose() }
        case .fullscreen:
            SoundEffectService.shared.play(.click)
            config.fullscreen.toggle()
        case .fps60:
            SoundEffectService.shared.play(.click)
            config.enable60FPS.toggle()
        case .metalFX:
            SoundEffectService.shared.play(.click)
            config.enableMetalFXUpscale.toggle()
        case .metalHUD:
            SoundEffectService.shared.play(.click)
            config.enableMetalHUD.toggle()
        case .consoleMode, .language, .rumbleStrength, .renderScale, .frameRate, .gameUpscaler:
            adjust(row, by: 1)
        case .moreSettings:
            SoundEffectService.shared.play(.click)
            moreOpen = true
        case .rumble:
            SoundEffectService.shared.play(.click)
            config.rumble.toggle()
        case .restoreDefaults:
            SoundEffectService.shared.play(.click)
            if snapshot != nil {
                viewModel.runtimeSettings.restoreGameDefaults(for: current)
                snapshot = viewModel.runtimeSettings.settingsSnapshot(for: current)
            } else {
                config = viewModel.settingsStore?.settings.gameDefaults ?? GameRuntimeConfig()
            }
        case .cheats:
            SoundEffectService.shared.play(.click)
            cheatsOpen = true
        case .mods:
            SoundEffectService.shared.play(.click)
            modsOpen = true
        case .rebuild:
            rebuild(current)
        case .showInFinder:
            SoundEffectService.shared.play(.click)
            viewModel.revealInFinder(url: current.url)
        case .openSaves:
            SoundEffectService.shared.play(.click)
            savesOpen = true
        case .editDetails:
            SoundEffectService.shared.play(.click)
            enterEditDetails()
        case .removeGame:
            SoundEffectService.shared.play(.click)
            askConfirm(.removeGame)
        case .changeArtwork:
            SoundEffectService.shared.play(.click)
            // The official name helps the cover search, as on the Collection.
            store.loadStoreMetadata(for: current)
            artworkOpen = true
        case .changeMetadata:
            SoundEffectService.shared.play(.click)
            // Automatic is the store's metadata; ask for it if it is not here yet.
            store.loadStoreMetadata(for: current)
            metadataOpen = true
        case .storePage:
            guard let url = store.storeMetadata[game.id]?.storeURL else { return }
            SoundEffectService.shared.play(.click)
            viewModel.openURL(url)
        case .searchStore:
            guard let url = store.nintendoStoreSearchURL(for: current) else { return }
            SoundEffectService.shared.play(.click)
            viewModel.openURL(url)
        case .attachSources:
            SoundEffectService.shared.play(.click)
            viewModel.locateSources(for: current)
        case .openLog:
            SoundEffectService.shared.play(.click)
            viewModel.revealLog(for: current)
        case .removeSources:
            SoundEffectService.shared.play(.click)
            askConfirm(.removeSources)
        }
    }

    /// Rebuild. A dimmed row still runs the build, so the Metal gate explains a refusal
    /// through the usual alert; a build that starts opens Add Game with its progress.
    func rebuild(_ game: PortedGame) {
        guard !presentation.sourcesDetached else {
            SoundEffectService.shared.play(.error)
            return
        }
        SoundEffectService.shared.play(.click)
        viewModel.porting.startBuild(for: game)
        if viewModel.isBuilding {
            onClose()
            onShowBuild()
        }
    }
}
