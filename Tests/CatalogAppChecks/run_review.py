#!/usr/bin/env python3
"""Exercise the review regressions without opening the app or touching player data.

Compiles the actual store/loader and focus/menu methods. Replaces only their
surrounding UI state and external services; Core readers use generated files.
Run after swift test, like run_notices.py.
"""
from pathlib import Path
import os
import struct
import subprocess
import tempfile
import re

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / '.build/debug'


def declaration(path, signature):
    source = (ROOT / path).read_text()
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def binary_kv(entries):
    data = bytearray()
    for key, value in entries:
        data.append(0 if isinstance(value, list) else 2 if isinstance(value, int) else 1)
        data.extend(key.encode() + b'\0')
        if isinstance(value, list):
            data.extend(binary_kv(value))
        elif isinstance(value, int):
            data.extend(struct.pack('<i', value))
        else:
            data.extend(value.encode() + b'\0')
    data.append(8)
    return data


host = r'''
import Foundation
import Combine
import NXLibraryCore

@MainActor var failures = 0
@MainActor func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { failures += 1; print("FAIL: " + message) }
}

// Only external enrichment is replaced: no network or player cache writes.
actor SteamMetadataService {
    static let shared = SteamMetadataService()
    func achievementPercents(appID: UInt32) -> [String: Double]? { [:] }
}
@MainActor final class ArtworkStore {
    enum Kind { case hero, logo }
    func cachedURL(titleID: String, kind: Kind) -> URL? { nil }
    func fetch(titleID: String, remoteURL: URL?, kind: Kind) async -> URL? { nil }
}
struct ArtworkPicks {
    static let shared = Self()
    func url(titleID: String, slot: ArtworkSlot) -> URL? { nil }
}
@MainActor enum OnlineArtwork {
    static var platforms: [CriticRatingQuery.Platform] = []
    static func find(names: [String], slot: ArtworkSlot? = nil,
                     platform: CriticRatingQuery.Platform = .switch) async -> [ArtworkCandidate] {
        platforms.append(platform)
        return []
    }
}

struct SpotlightPageModel { var links = [1]; var more: [Int] = [] }
final class ModsHost { var localMods: Int? }
@MainActor final class ViewModel {
    var spotlight = SpotlightState(focus: .actions)
    var showSetupCheck = false
    var isGameOptionsOpen = false
    var alertMessage: String?
    var gameToClose: Int?
    var gameToRemove: Int?
    var launchOverlay: Int?
    var isBuilding = false
    var catalogBuildRecoveries: [Int] = []
    var currentFocusedCatalogGame: CatalogGame?
    var currentFocusedGame: PortedGame? { currentFocusedCatalogGame?.nxnativeGame }
}
@MainActor final class SoundEffectService {
    enum Cue { case focus }
    static let shared = SoundEffectService()
    var count = 0
    func play(_ cue: Cue) { count += 1 }
}
@MainActor final class ScrollHost {
    let viewModel = ViewModel()
    var currentPage: SpotlightPageModel? = SpotlightPageModel()
    var screenshotCount = 0
    var selectedAchievements: Int? = 1
    let modsHost = ModsHost()
    var scroll: Double = -200
    var holdScroll = false
    func offset(for area: SpotlightFocusArea) -> Double {
        [.pills: 0, .strip: -100, .achievements: -200, .actions: -300, .mods: -400, .more: -500][area]!
    }
    func mutate(_ change: (inout SpotlightState) -> Void) { change(&viewModel.spotlight) }
    func settle() { settleFocusOnScroll() }
    // ACTUAL_SCROLL
}

final class Router {
    var route = AppRoute.library
    var isScreenshotViewerOpen = false
    var isSearchPresented = false
    var isMenuPresented = false
    func openSettings(_ section: SettingsSection) { route = .settings(section) }
}
final class WindowState { var attachedSheet: Int?; var isSheet = false }
final class ApplicationState {
    var modalWindow: Int?
    var keyWindow: WindowState?
    var mainWindow: WindowState?
}
let NSApp = ApplicationState()
final class NativeMenus { var isTracking = false }
@MainActor final class GameControllerService {
    static let shared = GameControllerService()
    var onAction: ((GamepadAction) -> Void)?
}
@MainActor final class InputRecorder { var actions: [GamepadAction] = [] }
// ACTUAL_ACTION_NAMES
@MainActor struct SteamPlayCoordinator {
    static let shared = Self()
    func canPlay(_ game: CatalogGame) -> Bool { true }
}
// ACTUAL_AVAILABILITY_TYPE
@MainActor final class MenuHost {
    let router = Router()
    let viewModel = ViewModel()
    let nativeMenus = NativeMenus()
    var isCloseGameOpen = false
    var showsWelcome = false
    var showsSettingsNotice = false
    var showsInstallFailure = false
    var showsUpdateOffer = false
    var dialogActions: [GamepadAction] = []
    var isHomeRoute: Bool { router.route == .library || router.route == .collection }
    func availability() -> NativeMenuAvailability { nativeMenuAvailability }
    func connectController() {
        let viewModel = viewModel
        let router = router
        // ACTUAL_CONTROLLER
    }
    func settingsNoticeInput(_ action: GamepadAction) { dialogActions.append(action) }
    func installFailureInput(_ action: GamepadAction) { dialogActions.append(action) }
    func closeGameInput(_ action: GamepadAction) { dialogActions.append(action) }
    func removeGameInput(_ action: GamepadAction) { dialogActions.append(action) }
    func updateOfferInput(_ action: GamepadAction) { dialogActions.append(action) }
    func menuInput(_ action: GamepadAction) { dialogActions.append(action) }
    // ACTUAL_DIALOG
    // ACTUAL_MENU
}

@main struct Check {
    @MainActor static func main() async {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let store = SteamAchievementsStore()
        store.load(appID: 42, language: "english")
        store.setSources([.init(integration: .steam, isEnabled: true, rootURL: root)])
        for _ in 0..<200 where store.summaries[42] == nil {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        require(store.summaries[42]?.total == 1,
                "Selection requested before Steam sources must load when the source arrives")
        store.stop()

        for title in ["0100000000000001", "0400000000000001"] {
            let game = PortedGame(name: "Generated fixture", url: root.appendingPathComponent(title + ".app"),
                                  platform: .macApp, sizeBytes: 1, modificationDate: Date(), titleId: title)
            _ = await GameArtLoader.shared.logo(for: game, metadata: nil, artwork: ArtworkStore(), personalizations: .empty)
        }
        require(OnlineArtwork.platforms == [.switch, .switch2], "Automatic logo search must use each game's console")

        let scroll = ScrollHost()
        scroll.settle()
        require(scroll.viewModel.spotlight.focus == .achievements, "Wheel settling must reach the visible achievements card")
        let cues = SoundEffectService.shared.count
        scroll.settle()
        require(SoundEffectService.shared.count == cues, "Settling on the focused card must not play another focus cue")
        scroll.selectedAchievements = nil
        scroll.settle()
        require(scroll.viewModel.spotlight.focus == .actions, "A missing achievements card must not take focus")

        let menu = MenuHost()
        menu.viewModel.currentFocusedCatalogGame = .init(nxnative: PortedGame(name: "Fixture", url: root.appendingPathComponent("Game.app"),
            platform: .macApp, sizeBytes: 1, modificationDate: Date()))
        require(menu.availability().details, "Details must remain available for the selected game")
        let overlays: [(MenuHost, Bool) -> Void] = [
            { $0.router.isSearchPresented = $1 }, { $0.router.isScreenshotViewerOpen = $1 },
            { $0.viewModel.isGameOptionsOpen = $1 }, { $0.router.isMenuPresented = $1 },
            { $0.viewModel.showSetupCheck = $1 },
            { $0.isCloseGameOpen = $1 }, { $0.viewModel.launchOverlay = $1 ? 1 : nil }
        ]
        for (index, overlay) in overlays.enumerated() {
            overlay(menu, true)
            require(!menu.availability().details, "Details must be disabled under overlay \(index)")
            overlay(menu, false)
        }
        menu.viewModel.currentFocusedCatalogGame = .init(steam: .init(appID: 42, name: "Fixture"))
        require(menu.availability().details, "Steam Details must remain available in Spotlight")
        menu.router.route = .collection
        require(!menu.availability().details, "Steam must not acquire a separate Details screen in Collection")

        let input = MenuHost()
        input.connectController()
        let received = InputRecorder()
        let watch = NotificationCenter.default.addObserver(forName: .nxSpotlightGamepadAction,
                                                           object: nil, queue: nil) { note in
            MainActor.assumeIsolated {
                if let action = note.object as? GamepadAction { received.actions.append(action) }
            }
        }
        defer { NotificationCenter.default.removeObserver(watch); GameControllerService.shared.onAction = nil }
        GameControllerService.shared.onAction?(.confirm)
        require(received.actions == [.confirm], "An uncovered library must receive controller actions")
        received.actions = []
        let blockers: [(String, (Bool) -> Void)] = [
            ("pending alert", { input.viewModel.alertMessage = $0 ? "Fixture alert" : nil }),
            ("modal dialog", { NSApp.modalWindow = $0 ? 1 : nil }),
            ("key sheet", { NSApp.keyWindow = $0 ? WindowState() : nil; NSApp.keyWindow?.isSheet = $0 }),
            ("sheet on key window", { NSApp.keyWindow = $0 ? WindowState() : nil; NSApp.keyWindow?.attachedSheet = $0 ? 1 : nil }),
            ("sheet on main window, no key window", { NSApp.mainWindow = $0 ? WindowState() : nil; NSApp.mainWindow?.attachedSheet = $0 ? 1 : nil }),
            ("native menu", { input.nativeMenus.isTracking = $0 })
        ]
        for (name, block) in blockers {
            block(true)
            for action: GamepadAction in [.navigateRight, .confirm, .cancel, .menu, .menuHold] {
                GameControllerService.shared.onAction?(action)
            }
            require(received.actions.isEmpty && input.router.route == .library && !input.router.isMenuPresented,
                    "Controller must not navigate or launch underneath \(name)")
            if name != "native menu" {
                require(!input.availability().general, "Native menu commands must yield to \(name)")
            }
            // An internal update confirmation is also below the native window.
            input.showsUpdateOffer = true
            input.isCloseGameOpen = true
            GameControllerService.shared.onAction?(.confirm)
            require(input.dialogActions.isEmpty, "The update dialog must not receive input underneath \(name)")
            input.showsUpdateOffer = false
            input.isCloseGameOpen = false
            block(false)
            input.router.route = .library
            input.router.isMenuPresented = false
            received.actions = []
            GameControllerService.shared.onAction?(.navigateLeft)
            require(received.actions == [.navigateLeft], "Closing \(name) must restore fresh input without replaying blocked actions")
            received.actions = []
            input.dialogActions = []
        }
        input.showsUpdateOffer = true
        input.isCloseGameOpen = true
        GameControllerService.shared.onAction?(.confirm)
        require(input.dialogActions == [.confirm] && received.actions.isEmpty,
                "An internal update dialog must still receive input when no native window is open")
        if failures > 0 { exit(1) }
        print("Actual app review checks passed: achievement startup, logo platform, wheel focus, native dialogs and input routing.")
    }
}
'''

host = host.replace('// ACTUAL_SCROLL', declaration(
    'Sources/NXLibrary/Views/Spotlight/SpotlightView+Input.swift', '    private func settleFocusOnScroll()'))
host = host.replace('// ACTUAL_AVAILABILITY_TYPE', declaration(
    'Sources/NXLibrary/Services/NativeMenuCommands.swift', 'struct NativeMenuAvailability'))
host = host.replace('// ACTUAL_MENU', declaration(
    'Sources/NXLibrary/Views/Shell/AppShellView.swift', '    private var nativeMenuAvailability:'))
host = host.replace('// ACTUAL_DIALOG', declaration(
    'Sources/NXLibrary/Views/Shell/AppShellView.swift', '    private var nativeDialogOwnsInput:'))
controller = declaration('Sources/NXLibrary/Views/Shell/AppShellView.swift',
                         '        GameControllerService.shared.onAction =')
host = host.replace('// ACTUAL_CONTROLLER', controller.replace('[weak viewModel, weak router]', '[self, weak viewModel, weak router]'))
names = sorted(set(re.findall(r'name: \.(nx\w+)', controller)))
host = host.replace('// ACTUAL_ACTION_NAMES', 'extension Notification.Name {\n' + '\n'.join(
    f'    static let {name} = Notification.Name("{name}")' for name in names) + '\n}')

with tempfile.TemporaryDirectory(prefix='catalog-review-check-') as folder:
    scratch = Path(folder)
    (scratch / 'config').mkdir()
    (scratch / 'config/loginusers.vdf').write_text('"users" { "76561197960265735" { "MostRecent" "1" } }')
    stats = scratch / 'appcache/stats'
    stats.mkdir(parents=True)
    schema = [('42', [('stats', [('1', [('bits', [('0', [
        ('name', 'FIRST'), ('display', [('name', [('english', 'First')])])])])])])])]
    (stats / 'UserGameStatsSchema_42.bin').write_bytes(binary_kv(schema))
    (stats / 'UserGameStats_7_42.bin').write_bytes(binary_kv([('cache', [('1', [('AchievementTimes', [('0', 10)])])])]))
    swift = scratch / 'check.swift'
    swift.write_text(host)
    executable = scratch / 'check'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-I', str(BIN), str(swift),
                    str(ROOT / 'Sources/NXLibrary/Services/SteamAchievementsStore.swift'),
                    str(ROOT / 'Sources/NXLibrary/Views/Spotlight/GameArtLoader.swift'),
                    str(ROOT / 'Sources/NXLibrary/Models/GamepadType.swift'),
                    str(BIN / 'NXLibraryCore.o'), '-o', str(executable)], cwd=ROOT, check=True)
    subprocess.run([str(executable), str(scratch)], check=True,
                   env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)))
