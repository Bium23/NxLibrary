#!/usr/bin/env python3
"""Exercise the real setup persistence and notification request sites without windows.

Only the surrounding app and notification transport are substituted. Preferences
use a unique synthetic domain; no player profile or game data is read.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / 'Sources/NXLibrary/ViewModels/AppViewModel.swift').read_text()


def declaration(signature, text=None):
    text = source if text is None else text
    start = text.index(signature)
    opening = text.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


initial = declaration('    public init(settingsStore:')
restore = initial[initial.index('        let didCompleteSetup = '):initial.index('        // 1. Resolve safe root')]
startup_requests = '\n'.join(line for line in initial.splitlines() if 'NotificationService.shared' in line)
build = declaration('    private func beginBuild(for game:')
accepted = build[build.index('        isBuilding = true'):build.index('        porting.buildState = .running')]
shell = (ROOT / 'Sources/NXLibrary/Views/Shell/AppShellView.swift').read_text()
start = shell.index('.onChange(of: viewModel.setupCompleted)')
opening = shell.index('{ done in', start)
depth, end = 1, opening + 1
while depth:
    depth += (shell[end] == '{') - (shell[end] == '}')
    end += 1
finish = shell[opening + len('{ done in'):end - 1]
found = (ROOT / 'Sources/NXLibrary/Views/Setup/FoundGamesSetupView.swift').read_text()
start = found.index('.onChange(of: findings)')
opening = found.index('{ found in', start)
depth, end = 1, opening + 1
while depth:
    depth += (found[end] == '{') - (found[end] == '}')
    end += 1
findings_changed = found[opening + len('{ found in'):end - 1]

host = '''
import Foundation
import Combine
import NXLibraryCore

enum AppData {
    static let domain = "local.nxlibrary.validation." + UUID().uuidString
    static let preferences = UserDefaults(suiteName: domain)!
}
enum NotificationRegistration { static var registered = false }
final class NotificationService {
    static let shared = NotificationService()
    var requests = 0
    init() { NotificationRegistration.registered = true }
    func requestAuthorization() { requests += 1 }
}
final class Host {
    // KEYS
    // SETUP
    var showSetupCheck = false
    var isBuilding = false
    final class Porting { var isCancellingBuild = false }
    let porting = Porting()
    let gameAppsFolder = URL(fileURLWithPath: "/synthetic/apps")
    init() {
        // RESTORE
        // STARTUP_REQUESTS
    }
    func chooseSteamOnFound(_ value: Bool) { firstRunSetup.chooseSteam(value) }
    func choose(_ value: Bool) { firstRunSetup.chooseSteam(value) }
    func openPorting() { firstRunSetup.openPorting() }
    func openPortingFromFound() { firstRunSetup.openPorting() }
    func finish() { firstRunSetup.finish() }
    func acceptBuild() {
        // ACCEPTED_BUILD
    }
}
final class Sources {
    struct Configuration { var isEnabled: Bool }
    var configuration: Configuration
    let discoveryRoot: URL
    var applied: [(Bool, URL?)] = []
    init(enabled: Bool, root: URL) { configuration = .init(isEnabled: enabled); discoveryRoot = root }
    func configure(enabled: Bool, root: URL?) { applied.append((enabled, root)); configuration.isEnabled = enabled }
}
final class Settings { var settings = AppSettings() }
final class Shell {
    let viewModel: Host
    let sources: Sources
    let settings = Settings()
    var showsWelcome = false
    init(model: Host, sources: Sources) { viewModel = model; self.sources = sources }
    func complete(_ done: Bool) {
        // FINISH
    }
}
struct NativeApp { var modalWindow: Int? }
var NSApp = NativeApp()
final class SoundEffectService {
    enum Cue { case click, key, error }
    static let shared = SoundEffectService()
    func play(_ cue: Cue) {}
}
final class FindingsReader {
    var cancellations = 0
    func cancel() { cancellations += 1 }
    func start(steamRoot: URL, appsFolder: URL) {}
}
final class FoundHost {
    let viewModel: Host
    var findings: FirstRunFindings?
    var focus = FirstRunSetup.Focus.steamToggle
    let reader = FindingsReader()
    let steamRoot = URL(fileURLWithPath: "/synthetic/Steam")
    var opened: [(ported: Bool, cancelled: Bool)] = []
    var steamCount: Int? { findings?.steamGameCount }
    var steamOn: Bool { viewModel.firstRunSetup.steamChoice ?? true }
    var portedCount: Int { findings?.portedAppCount ?? 0 }
    var isReading: Bool { findings == nil }
    func onOpenLibrary(_ ported: Bool) { opened.append((ported, reader.cancellations > 0)) }
    // ACTIVATE_FOUND
    var hasSteam: Bool { findings?.steamGameCount != nil || findings?.steamReadFailed == true }
    init(_ viewModel: Host) { self.viewModel = viewModel }
    func move(to next: FirstRunSetup.Focus) { focus = next }
    func receive(_ found: FirstRunFindings?) {
        findings = found
        // FINDINGS_CHANGED
    }
}
var failures = 0
func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { failures += 1; print("FAIL: " + message) }
}
defer { AppData.preferences.removePersistentDomain(forName: AppData.domain) }
let initialBoot = Host()
require(NotificationRegistration.registered, "Startup registers notification click handling without requesting authorization")
for value in [true, false] {
    AppData.preferences.removePersistentDomain(forName: AppData.domain)
    let before = Host()
    before.choose(value)
    before.openPorting()
    let resumed = Host()
    require(resumed.firstRunSetup.steamChoice == value, "Steam choice survives quit: \\(value)")
    require(resumed.firstRunSetup.page == .requirements, "Porting page survives quit")
    resumed.finish()
    require(resumed.firstRunSetup.steamChoice == value, "Shell can still apply the finishing choice")
    require(AppData.preferences.object(forKey: "NXLibrary_SetupSteamChoice") == nil, "Finishing removes saved choice")
    require(Host().firstRunSetup.steamChoice == nil, "Completed setup does not inherit a stale choice")
}
for enabled in [true, false] {
    for choice: Bool? in [true, false, nil] {
        AppData.preferences.removePersistentDomain(forName: AppData.domain)
        let model = Host()
        if let choice { model.choose(choice) }
        let custom = URL(fileURLWithPath: "/synthetic/Custom Steam")
        let sources = Sources(enabled: enabled, root: custom)
        let shell = Shell(model: model, sources: sources)
        shell.complete(false)
        require(sources.applied.isEmpty, "Incomplete setup does not apply the switch")
        model.finish()
        shell.complete(true)
        require(sources.configuration.isEnabled == (choice ?? enabled), "Finishing applies on and off, nil preserves the source")
        require(sources.applied.allSatisfy { $0.1 == custom }, "Opt-in uses the same custom root as discovery")
    }
}
AppData.preferences.removePersistentDomain(forName: AppData.domain)
let retryModel = Host()
retryModel.choose(false)
let retry = FoundHost(retryModel)
retry.receive(FirstRunFindings(steamGameCount: nil, portedAppCount: 0, steamReadFailed: true))
require(retry.focus == .steamToggle, "Retry row keeps focus while the read is incomplete")
retry.receive(nil)
retry.receive(FirstRunFindings(steamGameCount: nil, portedAppCount: 0))
require(retry.focus == .openLibrary, "Retry that finds no Steam leaves no invisible focused row")
retry.receive(FirstRunFindings(steamGameCount: 2, portedAppCount: 0))
require(retryModel.firstRunSetup.steamChoice == false, "Retry never resets an explicit off choice")
AppData.preferences.removePersistentDomain(forName: AppData.domain)
let waitingModel = Host()
waitingModel.showSetupCheck = true
let waiting = FoundHost(waitingModel)
waiting.activate(.openLibrary)
require(waiting.opened.count == 1 && waiting.opened.first?.ported == false,
        "A pending read does not block Open library or invent ported results")
require(waiting.opened.first?.cancelled == true, "Cancel the pending request before leaving the found page")
require(waitingModel.firstRunSetup.steamChoice == nil, "No unread source is opted in")
waiting.receive(FirstRunFindings(steamGameCount: 2, portedAppCount: 3))
waiting.activate(.openLibrary)
require(waiting.opened.last?.ported == true, "A completed read still imports found apps")
NSApp.modalWindow = 1
waiting.activate(.openLibrary)
require(waiting.opened.count == 2, "A native modal still owns input")
NSApp.modalWindow = nil
waitingModel.showSetupCheck = false
waiting.activate(.openLibrary)
require(waiting.opened.count == 2, "A departed setup does not finish again")
NotificationService.shared.requests = 0
let steamOnly = Host()
require(NotificationService.shared.requests == 0, "Startup and Steam-only use never request notifications")
NotificationService.shared.requests = 0
steamOnly.acceptBuild()
require(NotificationService.shared.requests == 1, "Accepted porting requests notifications")
if failures > 0 { exit(1) }
print("Onboarding persistence and notification timing: PASS")
'''
host = host.replace('// ACTIVATE_FOUND', declaration('    func activate(', (ROOT / 'Sources/NXLibrary/Views/Setup/FoundGamesSetupView+Input.swift').read_text()))
host = host.replace('// KEYS', declaration('    private enum StorageKeys'))
host = host.replace('// SETUP', declaration('    @Published public private(set) var firstRunSetup ='))
host = host.replace('// FINDINGS_CHANGED', findings_changed)
host = host.replace('// FINISH', finish)
host = host.replace('// RESTORE', restore).replace('// STARTUP_REQUESTS', startup_requests)
host = host.replace('// ACCEPTED_BUILD', accepted)
with tempfile.TemporaryDirectory(prefix='arcane-onboarding-check-') as scratch:
    scratch = Path(scratch)
    main = scratch / 'main.swift'
    main.write_text(host)
    binary = scratch / 'onboarding'
    library = ROOT / '.build/debug'
    subprocess.run(['xcrun', 'swiftc', '-I', str(library), str(main),
                    str(library / 'NXLibraryCore.o'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(library)), check=True)
