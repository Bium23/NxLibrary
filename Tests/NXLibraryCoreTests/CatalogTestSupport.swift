import Foundation
import XCTest
@testable import NXLibraryCore

enum CatalogTestSupport {
    static func completeLegacyGame(id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!) -> PortedGame {
        var game = PortedGame(id: id, name: "Fixture Switch game", url: URL(fileURLWithPath: "/tmp/catalog-fixture/Game.app"),
                              platform: .macApp, sizeBytes: 1234, modificationDate: Date(timeIntervalSince1970: 100),
                              bundleId: "org.nxnative.0100000000000001", titleId: "0100000000000001", versionString: "2.0")
        game.status = .builtSourcesMissing
        game.sources = [GameFileItem(url: URL(fileURLWithPath: "/tmp/catalog-fixture/base.nsp"), kind: .base,
                                    titleId: "0100000000000001", sizeBytes: 456)]
        game.workspacePath = "/tmp/catalog-fixture/workspace"
        game.buildCachePath = "/tmp/catalog-fixture/workspace/cache"
        game.settings.language = "it"
        game.settings.metalHUD = true
        game.toolchain = ToolchainInfo(engineCommit: "fixture123", metalVersion: "32023.922", xcodeVersion: "27.2", verified: true)
        game.lastBuild = BuildRecord(startedAt: Date(timeIntervalSince1970: 10), endedAt: Date(timeIntervalSince1970: 20),
                                     exitCode: 0, outputPath: game.url.path, toolchainVerified: true)
        game.pendingInstall = PendingInstall(tempApp: URL(fileURLWithPath: "/tmp/catalog-fixture/held/Game.app"), finalApp: game.url,
                                             record: game.lastBuild!, toolchain: game.toolchain)
        game.portingFailure = .failed
        game.portingFailureReason = PortingFailureReason(kind: .diskFull, detail: "Synthetic failure")
        game.isFavorite = true
        game.isHidden = true
        game.usesPickedAppIcon = true
        game.appIconOnMac = false
        game.appIconPending = true
        return game
    }

    static func writeLegacy(_ games: [PortedGame], to directory: URL, schemaVersion: Int = 1) throws -> Data {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LibraryFile(schemaVersion: schemaVersion, games: games))
        try data.write(to: directory.appendingPathComponent("library.json"))
        return data
    }
}
