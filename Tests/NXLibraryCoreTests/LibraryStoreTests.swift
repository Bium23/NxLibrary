import XCTest
@testable import NXLibraryCore

final class LibraryStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXLibraryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testExplicitSelectionReplacesExistingSourcesAndSurvivesLaterScans() throws {
        let store = LibraryStore(directory: dir.appendingPathComponent("catalog"))
        let app = dir.appendingPathComponent("Game.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let oldSource = dir.appendingPathComponent("old.nsp"), newSource = dir.appendingPathComponent("new.nsp")
        try Data("old".utf8).write(to: oldSource)
        try Data("new".utf8).write(to: newSource)
        var old = PortedGame(name: "Game", url: app, platform: .macApp, sizeBytes: 1,
                             modificationDate: Date(), titleId: "0100000000000001")
        old.status = .built
        old.isFavorite = true
        old.settings.language = "it"
        old.sources = [GameFileItem(url: oldSource, kind: .base, sizeBytes: 3)]
        old.workspacePath = dir.appendingPathComponent("old-workspace").path
        old.buildCachePath = dir.appendingPathComponent("old-cache").path
        try store.save(LibraryFile(games: [old]))
        var selected = old
        selected.url = dir.appendingPathComponent("new-workspace")
        selected.sources = [GameFileItem(url: newSource, kind: .base, sizeBytes: 3)]
        selected.workspacePath = selected.url.path
        selected.buildCachePath = dir.appendingPathComponent("new-cache").path
        let result = try XCTUnwrap(try store.merge(scanned: [selected], replacingSources: true).games.first)
        XCTAssertEqual(result.sources, selected.sources)
        XCTAssertEqual(result.workspacePath, selected.workspacePath)
        XCTAssertEqual(result.buildCachePath, selected.buildCachePath)
        XCTAssertEqual(result.url, app)
        XCTAssertEqual(result.id, old.id)
        XCTAssertEqual(result.settings, old.settings)
        XCTAssertTrue(result.isFavorite)
        var scanned = selected
        scanned.sources = []
        let refreshed = try XCTUnwrap(try store.merge(scanned: [scanned]).games.first)
        XCTAssertEqual(refreshed.sources, selected.sources)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldSource.path), "Replacing a selection never deletes sources")
    }

    func testSaveLoadAndMergePreservesSettings() throws {
        let store = LibraryStore(directory: dir)
        var game = PortedGame(
            name: "The Legend of Zelda: Breath of the Wild",
            url: URL(fileURLWithPath: "/tmp/game.app"),
            platform: .macApp,
            sizeBytes: 17,
            modificationDate: Date(timeIntervalSince1970: 1),
            bundleId: "org.nxnative.01007ef00011e000",
            titleId: "01007EF00011E000",
            versionString: "1.9.0"
        )
        game.status = .builtSourcesMissing
        game.settings.metalHUD = true
        try store.save(LibraryFile(schemaVersion: 1, games: [game]))
        let loaded = try store.load()
        XCTAssertEqual(loaded.games.first?.status, .builtSourcesMissing)
        XCTAssertEqual(loaded.games.first?.settings.metalHUD, true)

        var scanned = game
        scanned.status = .built
        scanned.settings = GameRuntimeConfig()
        let merged = try store.merge(scanned: [scanned])
        XCTAssertEqual(merged.games.first?.status, .built)
        XCTAssertEqual(merged.games.first?.settings.metalHUD, true)
        XCTAssertEqual(merged.games.count, 1)
    }

    func testMergeKeepsFavoriteAndHidden() throws {
        let store = LibraryStore(directory: dir)
        var game = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/g.app"),
                              platform: .macApp, sizeBytes: 1,
                              modificationDate: Date(timeIntervalSince1970: 1),
                              titleId: "0100000000000001")
        game.isFavorite = true
        game.isHidden = true
        try store.save(LibraryFile(schemaVersion: 1, games: [game]))
        var scanned = game
        scanned.isFavorite = false
        scanned.isHidden = false
        let merged = try store.merge(scanned: [scanned])
        XCTAssertEqual(merged.games.first?.isFavorite, true)
        XCTAssertEqual(merged.games.first?.isHidden, true)
    }

    func testRepeatedScansKeepPendingInstallAndFailureDetails() throws {
        let apps = dir.appendingPathComponent("Applications")
        let app = apps.appendingPathComponent("Game.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "org.nxnative.0100000000000001",
                    "DMTitleID": "0100000000000001", "CFBundleName": "Game",
                    "CFBundleShortVersionString": "1.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let importer = ImportService()
        let store = LibraryStore(directory: dir.appendingPathComponent("store"))
        var game = try XCTUnwrap(importer.scan(directories: [apps]).first.map { importer.makeGame(from: $0) })
        game.isFavorite = true
        game.settings.metalHUD = true
        game.pendingInstall = PendingInstall(tempApp: dir.appendingPathComponent("waiting/Game.app"), finalApp: app,
            record: BuildRecord(startedAt: Date(timeIntervalSince1970: 1), engineCommit: "2716f78"),
            toolchain: ToolchainInfo(engineCommit: "2716f78"))
        game.portingFailure = .failed
        game.portingFailureReason = PortingFailureReason(kind: .diskFull, detail: "Synthetic failure")
        try store.save(LibraryFile(games: [game]))

        for _ in 0..<3 {
            let scanned = importer.scan(directories: [apps]).map { importer.makeGame(from: $0) }
            let merged = try store.merge(scanned: scanned)
            let saved = try XCTUnwrap(store.load().games.first)
            XCTAssertEqual(merged.games.count, 1)
            XCTAssertEqual(saved.id, game.id)
            XCTAssertEqual(saved.pendingInstall, game.pendingInstall)
            XCTAssertEqual(saved.portingFailure, game.portingFailure)
            XCTAssertEqual(saved.portingFailureReason, game.portingFailureReason)
            XCTAssertEqual(saved.settings, game.settings)
            XCTAssertTrue(saved.isFavorite)
        }
    }

    func testCorruptFileRestoresBackup() throws {
        let store = LibraryStore(directory: dir)
        var game = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/g.app"),
                              platform: .macApp, sizeBytes: 1, modificationDate: Date())
        game.titleId = "0100000000010000"
        try store.save(LibraryFile(schemaVersion: 1, games: [game]))
        try Data("not json".utf8).write(to: store.fileURL)
        let recovered = try store.load()
        XCTAssertEqual(recovered.games.count, 1)

        // Saving the recovered value must not replace the good backup with the
        // corrupt main file. Corrupt the main again and recover again.
        try store.save(recovered)
        try Data("still not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(try store.load().games.count, 1)
    }

    /// A library that cannot be read and has no backup is moved aside, never written over by the next save: the
    /// games in it can still be recovered by hand (or by a newer NX Library that reads it).
    func testUnreadableLibraryWithoutBackupIsKeptAside() throws {
        let store = LibraryStore(directory: dir)
        let damaged = Data(#"{"schemaVersion": 1, "games": [{"name": "#.utf8)
        try damaged.write(to: store.fileURL)
        XCTAssertEqual(try store.load().games.count, 0)
        try store.save(LibraryFile())
        let kept = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("library.json.damaged-") }
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(kept[0])), damaged)
    }

    func testLoadUsesBackupWhenMainIsMissing() throws {
        let store = LibraryStore(directory: dir)
        var game = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/g.app"),
                              platform: .macApp, sizeBytes: 1, modificationDate: Date())
        game.titleId = "0100000000010000"
        try store.save(LibraryFile(schemaVersion: 1, games: [game]))
        try FileManager.default.removeItem(at: store.fileURL)
        XCTAssertEqual(try store.load().games.count, 1)
    }

    func testMergePreservesBuildMetadataAndMarksMissingSources() throws {
        let store = LibraryStore(directory: dir)
        let sourceFile = dir.appendingPathComponent("Game [0100000000010000].nsp")
        try Data("x".utf8).write(to: sourceFile)
        var game = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/G.app"),
                              platform: .macApp, sizeBytes: 1, modificationDate: Date(),
                              titleId: "0100000000010000")
        game.status = .built
        game.sources = [GameFileItem(url: sourceFile, kind: .base,
                                     titleId: "0100000000010000", sizeBytes: 1)]
        game.toolchain = ToolchainInfo(engineCommit: "06b7b3e",
                                       metalVersion: "32023.921",
                                       xcodeVersion: "27.1", verified: true)
        game.lastBuild = BuildRecord(endedAt: Date(), exitCode: 0,
                                     outputPath: "/tmp/G.app", toolchainVerified: true)
        try store.save(LibraryFile(schemaVersion: 1, games: [game]))

        var imported = game
        imported.status = .builtSourcesMissing
        imported.toolchain = ToolchainInfo(note: "Imported build; build record unavailable")
        imported.lastBuild = nil
        imported.sources = []

        let merged = try store.merge(scanned: [imported])
        XCTAssertEqual(merged.games.first?.status, .built)
        XCTAssertEqual(merged.games.first?.toolchain.verified, true)
        XCTAssertEqual(merged.games.first?.lastBuild?.exitCode, 0)

        try FileManager.default.removeItem(at: sourceFile)
        let afterDeletion = try store.merge(scanned: [imported])
        XCTAssertEqual(afterDeletion.games.first?.status, .builtSourcesMissing)
        XCTAssertEqual(afterDeletion.games.first?.toolchain.verified, true)
    }

    func testAttachingSourcesKeepsTheImportedAppURL() throws {
        let store = LibraryStore(directory: dir)
        let app = dir.appendingPathComponent("Old.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let sourceFile = dir.appendingPathComponent("Game [0100000000010000].nsp")
        try Data("x".utf8).write(to: sourceFile)

        var imported = PortedGame(name: "G", url: app, platform: .macApp,
                                  sizeBytes: 17, modificationDate: Date(),
                                  bundleId: "org.nxnative.0100000000010000",
                                  titleId: "0100000000010000",
                                  versionString: "1.9.0")
        imported.status = .builtSourcesMissing
        try store.save(LibraryFile(schemaVersion: 1, games: [imported]))

        var added = PortedGame(name: "G", url: dir.appendingPathComponent("workspace"),
                               platform: .macApp, sizeBytes: 1, modificationDate: Date(),
                               titleId: "0100000000010000")
        added.status = .notBuilt
        added.sources = [GameFileItem(url: sourceFile, kind: .base,
                                      titleId: "0100000000010000", sizeBytes: 1)]
        added.bundleId = "org.nxnative.0100000000010000"
        added.versionString = "65536"

        let merged = try store.merge(scanned: [added])
        XCTAssertEqual(merged.games.first?.url, app)
        XCTAssertEqual(merged.games.first?.status, .built)
        XCTAssertEqual(merged.games.first?.versionString, "1.9.0")
        XCTAssertEqual(merged.games.first?.bundleId, "org.nxnative.0100000000010000")
    }

    func testLocateSourcesReplacesMissingRecordedSources() throws {
        let store = LibraryStore(directory: dir)
        let app = dir.appendingPathComponent("Game.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let oldSource = dir.appendingPathComponent("old.nsp")
        let newSource = dir.appendingPathComponent("new.nsp")
        try Data("new".utf8).write(to: newSource)

        var old = PortedGame(name: "G", url: app, platform: .macApp,
                             sizeBytes: 1, modificationDate: Date(),
                             titleId: "0100000000010000")
        old.status = .builtSourcesMissing
        old.sources = [GameFileItem(url: oldSource, kind: .base,
                                    titleId: "0100000000010000", sizeBytes: 1)]
        try store.save(LibraryFile(schemaVersion: 1, games: [old]))

        var scanned = PortedGame(name: "G", url: dir.appendingPathComponent("workspace"),
                                 platform: .macApp, sizeBytes: 1, modificationDate: Date(),
                                 titleId: "0100000000010000")
        scanned.status = .notBuilt
        scanned.sources = [GameFileItem(url: newSource, kind: .base,
                                        titleId: "0100000000010000", sizeBytes: 1)]

        let merged = try store.merge(scanned: [scanned])
        XCTAssertEqual(merged.games.first?.sources.first?.url, newSource)
        XCTAssertEqual(merged.games.first?.status, .built)
        XCTAssertEqual(merged.games.first?.url, app)
    }

    func testMergeTitleIdsCaseInsensitively() throws {
        let store = LibraryStore(directory: dir)
        var old = PortedGame(name: "G", url: URL(fileURLWithPath: "/tmp/G.app"),
                             platform: .macApp, sizeBytes: 1, modificationDate: Date(),
                             titleId: "01007EF00011E000")
        old.status = .builtSourcesMissing
        try store.save(LibraryFile(schemaVersion: 1, games: [old]))

        var scanned = old
        scanned.titleId = "01007ef00011e000"
        scanned.status = .builtSourcesMissing
        let merged = try store.merge(scanned: [scanned])
        XCTAssertEqual(merged.games.count, 1)
        XCTAssertEqual(merged.games.first?.titleId, "01007ef00011e000")
    }
}
