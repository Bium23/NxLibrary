#!/usr/bin/env python3
"""Check the artwork chosen by a recreated view before its first async task.

Compiles the actual artwork views and task bodies. An Image value records its
input instead of rendering; no window, screenshot or UI automation. Uses real
decoding and generated files, isolated picks and no network/player data.
"""
from pathlib import Path
import os
import plistlib
import struct
import subprocess
import tempfile
import zlib
import argparse

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / '.build/debug'
parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, default=ROOT,
                    help='Optional source snapshot for regression checks; Core stays in the main checkout.')
SOURCE = parser.parse_args().source_root


def task_body(source):
    start = source.index('.task(id:')
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[opening + 1:end - 1]


with tempfile.TemporaryDirectory(prefix='arcane-artwork-return-') as temporary:
    scratch = Path(temporary)
    for filename, path, old, new in (
        ('Native.swift', 'Sources/NXLibrary/Views/Components/SpotlightTileArtwork.swift',
         'ArtworkPicks.shared', 'Fixture.nativePicks'),
        ('Steam.swift', 'Sources/NXLibrary/Views/Catalog/SteamArtwork.swift',
         'SteamPersonalizations.shared.artwork', 'Fixture.steamPicks'),
    ):
        source = (SOURCE / path).read_text().replace(old, new).replace('private ', '')
        typename = 'SpotlightTileArtwork' if filename == 'Native.swift' else 'SteamArtwork'
        source += '\nextension ' + typename + ' { func loadForCheck() async {\n' + task_body(source) + '\n} }\n'
        (scratch / filename).write_text(source)
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    pixels = (b'\0' + b'\xe0\x30\x90\xff' * 16) * 16
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 16, 16, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')
    (scratch / 'image.png').write_bytes(png)
    pixels2 = (b'\0' + b'\x10\xe0\x10\xff' * 16) * 16
    png2 = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 16, 16, 8, 6, 0, 0, 0))
    png2 += chunk(b'IDAT', zlib.compress(pixels2)) + chunk(b'IEND', b'')
    (scratch / 'image2.png').write_bytes(png2)
    pixels3 = (b'\0' + b'\x20\x40\xf0\xff' * 16) * 16
    png3 = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 16, 16, 8, 6, 0, 0, 0))
    png3 += chunk(b'IDAT', zlib.compress(pixels3)) + chunk(b'IEND', b'')
    (scratch / 'image3.png').write_bytes(png3)
    app = scratch / 'Fixture.app'
    (app / 'Contents/Resources').mkdir(parents=True)
    (app / 'Contents/Resources/Icon.icns').write_bytes(png)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIconFile': 'Icon'}))
    automatic = scratch / 'artwork/0100000000001000/square.png'
    automatic.parent.mkdir(parents=True)
    automatic.write_bytes(png)
    host = scratch / 'check.swift'
    host.write_text(r'''
import SwiftUI
import AppKit
@testable import NXLibraryCore

@MainActor enum Fixture {
    static let root = URL(fileURLWithPath: CommandLine.arguments[1])
    static let nativePicks = ArtworkPicks(directory: root.appendingPathComponent("native-picks"))
    static let steamPicks = SteamPersonalizationStore(directory: root.appendingPathComponent("steam-picks"))
    static let artwork = ArtworkStore(cacheDirectory: root.appendingPathComponent("artwork"))
}
@MainActor enum Capture { static var image: NSImage? }
struct Image: View {
    init(nsImage: NSImage) { Capture.image = nsImage }
    init(systemName: String) { Capture.image = nil }
    func resizable() -> Self { self }
    func interpolation(_ value: SwiftUI.Image.Interpolation) -> Self { self }
    var body: some View { Color.clear }
}
enum SeleneTheme { static var glassSolid: Color { .gray } }
struct Canvas { func u(_ value: CGFloat) -> CGFloat { value } }
struct CanvasKey: EnvironmentKey { static let defaultValue = Canvas() }
extension EnvironmentValues {
    var seleneCanvas: Canvas { get { self[CanvasKey.self] } set { self[CanvasKey.self] = newValue } }
}
@MainActor enum GameIconProvider {
    static let generic = NSImage(size: NSSize(width: 32, height: 32))
    static var own: NSImage?
    static func squareArt(for game: PortedGame) -> NSImage? { own }
    static func icon(for game: PortedGame) -> NSImage { generic }
}
@MainActor enum AppViewModel { static var automaticIconArtwork: ArtworkStore { Fixture.artwork } }
@MainActor enum OnlineArtwork {
    static func find(names: [String], slot: ArtworkSlot? = nil,
                     platform: CriticRatingQuery.Platform = .switch) async -> [ArtworkCandidate] { [] }
}
@main struct Check {
    @MainActor static func main() async throws {
        var failures = 0
        func require(_ value: Bool, _ message: String) {
            if value { print("PASS: " + message) }
            else { failures += 1; print("FAIL: " + message) }
        }
        func draw<V: View>(_ view: V) -> NSImage? {
            Capture.image = nil
            _ = view.body
            return Capture.image
        }
        let root = Fixture.root
        let png = try Data(contentsOf: root.appendingPathComponent("image.png"))
        var native = PortedGame(name: "Fixture", url: root.appendingPathComponent("not-built"),
                                platform: .macApp, sizeBytes: 0, modificationDate: Date())
        native.titleId = "0100000000001000"
        let automatic = SpotlightTileArtwork(game: native, side: 160, artwork: Fixture.artwork, ownIconFirst: true)
        await automatic.loadForCheck()
        let returned = SpotlightTileArtwork(game: native, side: 160, artwork: Fixture.artwork, ownIconFirst: true)
        require(draw(returned).map { $0 !== GameIconProvider.generic } == true,
                "nxnative automatic art is present before the recreated view's task")

        try Fixture.nativePicks.save(png, titleID: native.titleId!, slot: .icon)
        let personal = SpotlightTileArtwork(game: native, side: 160, artwork: Fixture.artwork, ownIconFirst: true)
        await personal.loadForCheck()
        let personalReturn = SpotlightTileArtwork(game: native, side: 160, artwork: Fixture.artwork, ownIconFirst: true)
        let personalImage = draw(personalReturn)
        require(personalImage.map { $0 !== GameIconProvider.generic } == true,
                "nxnative personal art is present before the recreated view's task")
        Fixture.nativePicks.remove(titleID: native.titleId!, slot: .icon)
        let noPick = SpotlightTileArtwork(game: native, side: 160, artwork: Fixture.artwork, ownIconFirst: true)
        require(personalImage == nil || draw(noPick) !== personalImage,
                "removing a pick does not reuse its decoded image")

        let app = root.appendingPathComponent("Fixture.app")
        let observed = NativeMacApplication(url: app, executableURL: app.appendingPathComponent("Contents/MacOS/main"),
            bundleIdentifier: "fixture", name: "Fixture", architectures: [.arm64], isDeclaredGame: true, fileObservations: [])
        var steam = SteamCatalogGame(appID: 10, name: "Fixture")
        steam.installations = [.init(libraryURL: root, contentURL: root,
            applications: [CatalogNativeApplication(observed)], availability: .available)]
        let game = CatalogGame(steam: steam)
        let square = SteamArtwork(game: game, slot: .icon)
        await square.loadForCheck()
        let squareReturn = SteamArtwork(game: game, slot: .icon)
        require(draw(squareReturn) != nil, "Steam app artwork is present before the recreated view's task")

        func color(_ image: NSImage?) -> String? {
            guard let data = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
                  let pixel = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else { return nil }
            return "\(Int((pixel.redComponent * 255).rounded())),\(Int((pixel.greenComponent * 255).rounded())),\(Int((pixel.blueComponent * 255).rounded()))"
        }
        let iconFile = app.appendingPathComponent("Contents/Resources/Icon.icns")
        let replacement = try Data(contentsOf: root.appendingPathComponent("image2.png"))
        try replacement.write(to: iconFile, options: .atomic)
        var updatedSteam = steam
        updatedSteam.installations[0].buildID = "updated-build"
        let updatedGame = CatalogGame(steam: updatedSteam)
        await SteamArtwork(game: updatedGame, slot: .icon).loadForCheck()
        let freshFile = await GameArtLoader.decode(at: iconFile, maxPixelSize: 512)
        require(color(draw(SteamArtwork(game: updatedGame, slot: .icon))) == color(freshFile),
                "Steam update at the same app path replaces the decoded icon")
        // Even a file replaced without a new build ID is revalidated behind the warm first frame.
        try Data(contentsOf: root.appendingPathComponent("image3.png")).write(to: iconFile, options: .atomic)
        await SteamArtwork(game: updatedGame, slot: .icon).loadForCheck()
        let resetFile = await GameArtLoader.decode(at: iconFile, maxPixelSize: 512)
        require(color(draw(SteamArtwork(game: updatedGame, slot: .icon))) == color(resetFile),
                "an unchanged build ID cannot keep stale pixels indefinitely")

        try Fixture.steamPicks.save(fields: [:], images: [.icon: png], automatic: [], titleID: game.personalizationReference.key)
        let steamPick = SteamArtwork(game: game, slot: .icon)
        await steamPick.loadForCheck()
        let steamPickReturn = SteamArtwork(game: game, slot: .icon)
        let steamPersonal = draw(steamPickReturn)
        require(steamPersonal != nil, "Steam personal artwork is present before the recreated view's task")
        try Fixture.steamPicks.save(fields: [:], images: [:], automatic: [.icon], titleID: game.personalizationReference.key)
        let steamReset = SteamArtwork(game: game, slot: .icon)
        require(steamPersonal == nil || draw(steamReset) !== steamPersonal,
                "Steam Automatic does not reuse the removed personal image")
        let remoteChanged = SteamArtwork(game: game, slot: .icon, remote: URL(string: "https://fixture.invalid/other.png"))
        require(steamPersonal == nil || draw(remoteChanged) !== steamPersonal,
                "a different request cannot borrow the previous request's decoded image")
        exit(failures == 0 ? 0 : 1)
    }
}
''')
    executable = scratch / 'check'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-I', str(BIN), str(host),
                    str(scratch / 'Native.swift'), str(scratch / 'Steam.swift'),
                    str(ROOT / 'Sources/NXLibrary/Views/Spotlight/GameArtLoader.swift'),
                    str(ROOT / 'Sources/NXLibrary/Views/Theme/CatalogPersonalizationsEnvironment.swift'),
                    str(BIN / 'NXLibraryCore.o'), '-o', str(executable)], check=True)
    view_result = subprocess.run([str(executable), str(scratch)],
                                 env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)))

    mods = scratch / 'ModsCheck.swift'
    mods.write_text(r'''
import Foundation
import AppKit
import Combine
import NXLibraryCore

enum AppData { static let cacheRoot = URL(fileURLWithPath: CommandLine.arguments[1]) }
struct NoHTTP: ArtworkHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { fatalError("Network forbidden") }
}
final class GameBananaServices {
    static let shared = GameBananaServices()
    let matches = GameBananaMatchStore(file: AppData.cacheRoot.appendingPathComponent("matches.json"))
    let client = GameBananaClient(http: NoHTTP(), cacheFolder: AppData.cacheRoot.appendingPathComponent("api"), userAgent: "fixture")
}
@MainActor final class AppViewModel {
    let fixtureStore: ModStore
    var storeMetadata: [UUID: NintendoStoreMetadata] = [:]
    init(_ store: ModStore) { fixtureStore = store }
    func modStore(for game: PortedGame) -> ModStore? { fixtureStore }
}
@MainActor final class ModsBandHost: ObservableObject {
    let gameBanana = GameBananaBandModel(client: GameBananaServices.shared.client, matches: GameBananaServices.shared.matches, userAgent: "fixture")
    var isPanelOpen = false
    func reloadRecords(viewModel: AppViewModel) {}
    func stop() { gameBanana.stop(); isPanelOpen = false }
    func openStoreDetail(_ mod: AvailableMod, game: PortedGame, viewModel: AppViewModel) {}
}
enum GameBananaImageView {
    static func prepare(_ urls: [URL], maxPixelSize: Int) async {}
    static func prewarm(_ urls: [URL], maxPixelSize: Int) {}
}
enum ModsCardCover { static let pixelSize = 700 }
enum GameBananaBlur {
    static let bannerRadius = 10.0
    static func image(for url: URL, radius: Double) async {}
}
struct SoundEffectService {
    enum Cue { case click, error }
    static let shared = Self()
    func play(_ cue: Cue) {}
}
struct CheckFailure: Error {}
enum CoverReadGate {
    static let captured = DispatchSemaphore(value: 0)
    static let resume = DispatchSemaphore(value: 0)
    static let completed = DispatchSemaphore(value: 0)
    static let lock = NSLock()
    private static var armed = false
    private static var held: UUID?
    static func arm() { lock.lock(); armed = true; lock.unlock() }
    static func didRead(_ id: UUID) {
        lock.lock()
        let hold = armed
        if hold { armed = false; held = id }
        lock.unlock()
        if hold {
            captured.signal()
            precondition(resume.wait(timeout: .now() + 5) == .success)
        }
    }
    static func finished(_ id: UUID) {
        lock.lock(); let matches = held == id; lock.unlock()
        if matches { completed.signal() }
    }
}
@main struct ModsCheck {
    @MainActor static func waitFor(_ message: String = "async fixture becomes ready", _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { print("FAIL: " + message); throw CheckFailure() }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { print("FAIL: " + message); throw CheckFailure() }
        print("PASS: " + message)
    }
    @MainActor static func main() async {
        do { try await check() }
        catch { print("FAIL: Mods fixture: \(error)"); exit(1) }
    }
    @MainActor static func check() async throws {
        let root = AppData.cacheRoot
        let tid = "0100000000010000"
        let mod = AvailableMod(id: 10, rank: 0, name: "Fixture mod", author: "Fixture", avatarURL: nil,
            images: [URL(string: "https://images.gamebanana.com/img/ss/mods/fixture.png")!], thumbnailURL: nil,
            version: "", updated: Date(), pageURL: URL(string: "https://gamebanana.com/mods/10")!, description: "", likes: 0, downloads: 0,
            files: [GameBananaFile(id: 100, name: "fixture.zip", size: 1, downloadURL: URL(string: "https://gamebanana.com/dl/100"), md5: "fixture")])
        let matches = GameBananaServices.shared.matches
        try matches.set(.game(id: 1, name: "Fixture", profileURL: URL(string: "https://gamebanana.com/games/1")!), titleID: tid)
        let snapshots = ModCatalogSnapshots(folder: root.appendingPathComponent("gamebanana/store"))
        try snapshots.save([mod], gameName: "Fixture", titleID: tid, gameBananaID: 1)
        let store = ModStore(supportFolder: root.appendingPathComponent("support"), recordsFile: root.appendingPathComponent("records.json"), titleID: tid,
            canWrite: { true }, trash: { _ in fatalError("Trash forbidden") }, allowsAutomaticMaintenance: false)
        let folder = store.modsFolder.appendingPathComponent("fixture")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("romfs"), withIntermediateDirectories: true)
        try Data([0]).write(to: folder.appendingPathComponent("romfs/a.bin"))
        try JSONEncoder().encode([ModRecord(folderName: "fixture", isOn: true, gameBananaModID: 10, gameBananaFileID: 100, md5: "fixture")]).write(to: store.recordsFile)
        let model = AppViewModel(store)
        var game = PortedGame(name: "Fixture", url: root.appendingPathComponent("Fixture.app"), platform: .macApp, sizeBytes: 0, modificationDate: Date())
        game.titleId = tid
        let host = ModStoreHost()
        host.loadCover(titleIDs: [tid]); host.open([game], viewModel: model)
        try await waitFor { host.records[tid]?[10] != nil && !host.cover.isEmpty }
        let prepared = host.cover
        host.close()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        for _ in 0..<10 { await Task.yield() }
        try require(host.cover == prepared, "closing the store keeps its prepared cover")
        try FileManager.default.removeItem(at: folder)
        host.open([game], viewModel: model)
        try await waitFor("reopening refreshes records after external removal") { host.records[tid]?.isEmpty == true }
        try require(host.chip(for: ModCatalogEntry(mod: mod, titleID: tid, gameName: "Fixture")) == nil,
                    "reopening refreshes badges after a mod was removed elsewhere")
        host.close()
        try matches.set(.noPage, titleID: tid)
        host.loadCover(titleIDs: [tid])
        try await waitFor { host.cover.isEmpty }
        try require(host.cover.isEmpty, "None of these removes a retained cover")
        try matches.set(.game(id: 1, name: "Fixture", profileURL: URL(string: "https://gamebanana.com/games/1")!), titleID: tid)
        host.loadCover(titleIDs: [tid])
        try await waitFor { !host.cover.isEmpty }
        try matches.set(.game(id: 2, name: "Other", profileURL: URL(string: "https://gamebanana.com/games/2")!), titleID: tid)
        host.loadCover(titleIDs: [tid])
        try await waitFor { host.cover.isEmpty }
        try require(host.cover.isEmpty, "a changed match rejects a snapshot of another GameBanana page")

        try matches.set(.game(id: 1, name: "Fixture", profileURL: URL(string: "https://gamebanana.com/games/1")!), titleID: tid)
        CoverReadGate.arm()
        host.loadCover(titleIDs: [tid])
        try await waitFor { CoverReadGate.captured.wait(timeout: .now()) == .success }
        let fresh = AvailableMod(id: 20, rank: 0, name: "Fresh", author: "Fixture", avatarURL: nil,
            images: [URL(string: "https://images.gamebanana.com/img/ss/mods/fresh.png")!], thumbnailURL: nil,
            version: "", updated: Date(), pageURL: URL(string: "https://gamebanana.com/mods/20")!,
            description: "", likes: 0, downloads: 0, files: mod.files)
        try snapshots.save([fresh], gameName: "Fixture", titleID: tid, gameBananaID: 1)
        host.open([game], viewModel: model)
        try await waitFor { host.cover == fresh.images }
        CoverReadGate.resume.signal()
        try await waitFor { CoverReadGate.completed.wait(timeout: .now()) == .success }
        try require(host.cover == fresh.images && host.catalog.games.first?.mods.first?.id == 20,
                    "an older snapshot cannot replace a newer catalog cover")
        host.close()
    }
}
''')
    mods_executable = scratch / 'mods-check'
    model_source = (SOURCE / 'Sources/NXLibrary/ViewModels/ModStoreHost.swift').read_text()
    assert model_source.count('return ModStoreLayout.coverArt(games: games)') == 1
    # Control only the filesystem-read completion, leaving the production
    # publication/generation checks and all model callbacks intact.
    model_source = model_source.replace('return ModStoreLayout.coverArt(games: games)',
        'CoverReadGate.didRead(requestID); return ModStoreLayout.coverArt(games: games)')
    assert model_source.count('            guard let self, self.coverTitleIDs') == 1
    model_source = model_source.replace('            guard let self, self.coverTitleIDs',
        '            defer { CoverReadGate.finished(requestID) }\n            guard let self, self.coverTitleIDs')
    assert model_source.count('            self.show(cover: urls)') == 1
    model_source = model_source.replace('            self.show(cover: urls)',
        '            self.show(cover: urls)\n            _ = await self.coverTask?.value')
    controlled_host = scratch / 'ControlledHost.swift'
    controlled_host.write_text(model_source)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-I', str(BIN), str(mods),
                    str(controlled_host),
                    str(ROOT / 'Sources/NXLibrary/Models/GamepadType.swift'),
                    str(BIN / 'NXLibraryCore.o'), '-o', str(mods_executable)], check=True)
    mods_result = subprocess.run([str(mods_executable), str(scratch)],
                                 env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)))
    raise SystemExit(view_result.returncode or mods_result.returncode)
