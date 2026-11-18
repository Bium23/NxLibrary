#!/usr/bin/env python3
"""Exercise the actual startup recovery coordinator with isolated catalogs, no windows.

Only profile selection/preparation and shell construction are substituted. The
catalog, conflict candidates, archives and recovery operations are real Core I/O.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / '.build/debug'
source = (ROOT / 'Sources/NXLibrary/Views/Launch/DevelopmentStartupView.swift').read_text()
start = source.index('@MainActor\nfinal class DevelopmentStartup:')
end = source.index('\nprivate enum DevelopmentStartupFailure:', start)
coordinator = source[start:end]

host = r'''
import Foundation
import AppKit
import Combine
import NXLibraryCore
import os

enum AppData {
    static var supportRoot = URL(fileURLWithPath: "/unused")
    static var rejectPreparation = false
    struct Profile { var isDevelopment = false }
    static let profile = Profile()
    static func prepare() throws {
        if rejectPreparation { throw CocoaError(.fileReadNoPermission) }
    }
}
struct AppSettingsStore {}
final class AppShellState {
    let catalog: CatalogDocument
    init(settings: AppSettingsStore, catalog: CatalogDocument, repository: CatalogRepository) {
        self.catalog = catalog
    }
}
enum DevelopmentStartupFailure: Error { case otherCopyRunning }
// ACTUAL_COORDINATOR

@main struct Check {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        AppData.supportRoot = root
        let store = CatalogStore(directory: root)
        var mixed = try store.loadOrMigrate()
        mixed.games.append(.init(steam: SteamCatalogGame(appID: 42, name: "Fixture")))
        mixed = try store.save(mixed, expectedRevision: mixed.revision)
        let legacy = root.appendingPathComponent("library.json")
        // Older app creates a legacy library after an initially empty migration.
        try Data("older-app bytes".utf8).write(to: legacy)

        let startup = DevelopmentStartup()
        await startup.prepare()
        precondition(startup.shell == nil && startup.failure != nil)
        precondition(startup.legacyConflict != nil && startup.recovery == nil && !startup.working)
        await startup.keepCurrentLibrary()
        precondition(startup.shell?.catalog.games == mixed.games)
        precondition(startup.failure == nil && startup.legacyConflict == nil && !startup.working)
        let unchangedLegacy = try Data(contentsOf: legacy)
        precondition(unchangedLegacy == Data("older-app bytes".utf8))

        try Data("second edit".utf8).write(to: legacy)
        let stale = DevelopmentStartup()
        await stale.prepare()
        precondition(stale.legacyConflict != nil && stale.shell == nil)
        try Data("third edit".utf8).write(to: legacy)
        await stale.keepCurrentLibrary()
        precondition(stale.shell == nil && stale.legacyConflict == nil && !stale.working)
        precondition(stale.failure != nil)
        await stale.prepare()
        precondition(stale.legacyConflict != nil)
        await stale.keepCurrentLibrary()
        precondition(stale.shell?.catalog.games == mixed.games)

        let healthy = DevelopmentStartup()
        await healthy.prepare()
        precondition(healthy.shell != nil && healthy.legacyConflict == nil && healthy.recovery == nil)

        AppData.rejectPreparation = true
        let blocked = DevelopmentStartup()
        await blocked.prepare()
        precondition(blocked.shell == nil && blocked.failure != nil && !blocked.working)
        precondition(blocked.legacyConflict == nil && blocked.recovery == nil)
        AppData.rejectPreparation = false
        await blocked.prepare()
        precondition(blocked.shell != nil && blocked.failure == nil)
        print("Actual startup recovery checks passed: conflict, explicit keep, stale offer, retry, healthy startup and preparation failure.")
    }
}
'''.replace('// ACTUAL_COORDINATOR', coordinator)

with tempfile.TemporaryDirectory(prefix='catalog-startup-recovery-') as folder:
    scratch = Path(folder)
    swift = scratch / 'check.swift'
    swift.write_text(host)
    executable = scratch / 'check'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-I', str(BIN), str(swift),
                    str(BIN / 'NXLibraryCore.o'), '-o', str(executable)], cwd=ROOT, check=True)
    subprocess.run([str(executable), str(scratch / 'profile')], check=True,
                   env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)))
