#!/usr/bin/env python3
"""Check source-access triggers using the real startup block, observer and pickers.

No AppKit windows or player data: replace the picker and the scanner I/O boundary,
then count requests made by the actual AppViewModel code, as in run_review.py.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / 'Sources/NXLibrary/ViewModels/AppViewModel.swift').read_text()


def declaration(signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


startup = source[source.index('        restoreBuildInputs(automatic: true)'):
                 source.index('        recoverSavesAtStartup()')]
host = r'''
import Foundation
import Combine
import UniformTypeIdentifiers

final class Preferences {
    var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}
enum AppData {
    static let preferences = Preferences()
    struct Profile { var isDevelopment = false }
    static var profile = Profile()
}
enum StorageKeys { static let savedGameFolder = "fixture-folder" }
struct Startup { var checkEngineAtLaunch = true; var refreshLibraryAtLaunch = true }
struct GameRuntimeConfig {}
enum GameFoldersCopy {
    static func sourcesPickerMessage(extractedFolders: Bool) -> String { "Fixture picker" }
}

// Only the system picker is substituted. The production methods configure it
// and choose which scan to request; no permissions or real windows are involved.
final class NSOpenPanel {
    enum Response { case OK, cancel }
    static var response = Response.cancel
    static var picked: [URL] = []
    static var openedAt: URL?
    var canChooseFiles = false
    var canChooseDirectories = false
    var allowsMultipleSelection = false
    var directoryURL: URL?
    var prompt = ""
    var message = ""
    var allowedContentTypes: [UTType] = []
    var urls: [URL] { Self.picked }
    var url: URL? { urls.first }
    func runModal() -> Response { Self.openedAt = directoryURL; return Self.response }
}

final class SourceHost {
    private var keepsRememberedGameFolder = false
    private var restoringGameFolder = false
    private var selectedPackageURLs: [URL]?
    var scanGeneration = UUID()
    var detectedGames: [Int] = []
    var selectedGame: Int?
    var selectedSourceIDs: Set<UUID> = []
    var scanError: String?
    var isScanningGameFolder = false
    var engineSourceCapabilities = (extractedFolders: true, unused: false)
    var scans: [(folder: URL, files: [URL]?)] = []
    // ACTUAL_FOLDER
    // ACTUAL_REMEMBERED_FOLDER
    // ACTUAL_FOLDER_PICKER
    // ACTUAL_FILE_PICKER
    func restoreBuildInputs(automatic: Bool) {}
    func refreshCompatibility() {}
    func startNewAddGame(defaults: GameRuntimeConfig) { selectedGameFolder = nil }
    func scanGameFolder(_ folder: URL) { scans.append((folder, selectedPackageURLs)) }
    func boot(_ startup: Startup) {
        let didCompleteSetup = true
        // ACTUAL_STARTUP
    }
}

@main struct Check {
    static func main() {
        var failures = 0
        func require(_ ok: @autoclosure () -> Bool, _ message: String) {
            if !ok() { failures += 1; print("FAIL: " + message) }
        }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Downloads")
        AppData.preferences.set(folder.path, forKey: StorageKeys.savedGameFolder)
        for development in [false, true] {
            AppData.profile.isDevelopment = development
            for refresh in [false, true] {
                let model = SourceHost()
                model.boot(Startup(refreshLibraryAtLaunch: refresh))
                require(model.scans.isEmpty, "Launch must not scan remembered sources (refresh=\(refresh), dev=\(development))")
                require(model.selectedGameFolder == nil, "Launch must leave the Add game draft empty")
                require(model.gameFilesFolder == folder, "Launch must keep the remembered folder preference")
            }
        }

        let model = SourceHost()
        model.boot(Startup())
        NSOpenPanel.response = .cancel
        require(!model.selectGameFolder(), "Cancelling the picker must return false")
        require(model.scans.isEmpty, "Cancelling the picker must not scan sources")
        require(NSOpenPanel.openedAt == folder, "The folder picker must start at the remembered folder")

        NSOpenPanel.response = .OK
        NSOpenPanel.picked = [folder]
        require(model.selectGameFolder(), "An explicit folder choice must be accepted")
        require(model.scans.count == 1 && model.scans.last?.folder == folder,
                "An explicit folder choice must request one scan")

        let otherFolder = folder.deletingLastPathComponent().appendingPathComponent("Other inputs")
        let files = [otherFolder.appendingPathComponent("chosen.nsp"), otherFolder.appendingPathComponent("update.nsp")]
        let filesModel = SourceHost()
        filesModel.boot(Startup())
        NSOpenPanel.picked = files
        require(filesModel.selectGameFiles(), "Explicit file choices must be accepted")
        require(filesModel.scans.count == 1 && filesModel.scans.last?.files == files,
                "Explicit files must request one scan limited to those files")
        require(filesModel.gameFilesFolder == folder, "File picks must preserve the remembered folder")
        if failures > 0 { exit(1) }
        print("Source access checks passed: no launch scan, remembered picker, cancel, explicit folder and files.")
    }
}
'''
for marker, signature in (
    ('// ACTUAL_FOLDER', '    @Published public var selectedGameFolder:'),
    ('// ACTUAL_REMEMBERED_FOLDER', '    public var gameFilesFolder:'),
    ('// ACTUAL_FOLDER_PICKER', '    public func selectGameFolder('),
    ('// ACTUAL_FILE_PICKER', '    public func selectGameFiles('),
):
    host = host.replace(marker + '\n', declaration(signature) + '\n')
host = host.replace('// ACTUAL_STARTUP', startup)
with tempfile.TemporaryDirectory(prefix='source-access-check-') as folder:
    scratch = Path(folder)
    swift = scratch / 'check.swift'
    swift.write_text(host)
    executable = scratch / 'check'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(swift), '-o', str(executable)], check=True)
    subprocess.run([str(executable), str(scratch)], check=True)
