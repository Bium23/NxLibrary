import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class CatalogRecoveryTests: XCTestCase {
    private func prepared() throws -> (URL, CatalogStore, CatalogDocument, Data) {
        let root = try SteamTestFixture.temporary(in: self).root
        let legacy = try CatalogTestSupport.writeLegacy([CatalogTestSupport.completeLegacyGame()], to: root)
        let store = CatalogStore(directory: root)
        return (root, store, try store.loadOrMigrate(), legacy)
    }
    private func file(_ root: URL, _ name: String) -> URL { root.appendingPathComponent(name) }

    func testExplicitRestorePreservesDamagedMainBackupAndOriginalLegacy() throws {
        let (root, store, original, legacy) = try prepared()
        let backup = try Data(contentsOf: file(root, "catalog.json.bak"))
        let damaged = Data("incomplete document".utf8)
        try damaged.write(to: file(root, "catalog.json"))
        let candidate = try XCTUnwrap(store.recoveryCandidate())
        XCTAssertEqual(candidate.gameCount, 1)
        XCTAssertEqual(try Data(contentsOf: file(root, "catalog.json")), damaged, "Offering recovery alone must not repair anything")
        let restored = try store.restoreBackup(candidate)
        XCTAssertEqual(restored.games, original.games)
        XCTAssertNotEqual(restored.revision, original.revision)
        XCTAssertEqual(try store.loadOrMigrate(), restored)
        let archives = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("catalog.json.recovered-") }
        XCTAssertEqual(archives.count, 1)
        XCTAssertEqual(try Data(contentsOf: archives[0]), damaged)
        XCTAssertEqual(try Data(contentsOf: file(root, "catalog.json.bak")), backup)
        XCTAssertEqual(try Data(contentsOf: file(root, "library.json")), legacy)
    }

    func testMissingMainCanBeRestoredExplicitlyAndHealthyMainHasNoOffer() throws {
        let (root, store, original, _) = try prepared()
        XCTAssertNil(try store.recoveryCandidate())
        try FileManager.default.removeItem(at: file(root, "catalog.json"))
        let candidate = try XCTUnwrap(store.recoveryCandidate())
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(root, "catalog.json").path))
        XCTAssertEqual(try store.restoreBackup(candidate).games, original.games)
        XCTAssertNil(try store.recoveryCandidate())
    }

    func testStaleRecoveryOfferCannotReplaceChangedMainOrBackup() throws {
        for changed in ["catalog.json", "catalog.json.bak"] {
            let (root, store, _, _) = try prepared()
            try Data("damaged".utf8).write(to: file(root, "catalog.json"))
            let candidate = try XCTUnwrap(store.recoveryCandidate())
            let later = Data("later edit".utf8)
            try later.write(to: file(root, changed))
            XCTAssertThrowsError(try store.restoreBackup(candidate)) { XCTAssertEqual($0 as? CatalogStoreError, .staleRevision) }
            XCTAssertEqual(try Data(contentsOf: file(root, changed)), later)
        }
    }

    func testChangedLegacyAndUnsafeBackupCannotBeRestored() throws {
        let (root, store, _, legacy) = try prepared()
        try Data("damaged".utf8).write(to: file(root, "catalog.json"))
        let candidate = try XCTUnwrap(store.recoveryCandidate())
        try (legacy + Data(" ".utf8)).write(to: file(root, "library.json"))
        XCTAssertThrowsError(try store.restoreBackup(candidate))
        XCTAssertThrowsError(try store.recoveryCandidate())
        try FileManager.default.removeItem(at: file(root, "catalog.json.bak"))
        try FileManager.default.createSymbolicLink(at: file(root, "catalog.json.bak"), withDestinationURL: file(root, "library.json"))
        XCTAssertThrowsError(try store.recoveryCandidate())
        XCTAssertEqual(try Data(contentsOf: file(root, "catalog.json")), Data("damaged".utf8))
    }

    func testRecoveryPublicationFailureLeavesAllInputsAvailable() throws {
        let (root, store, _, _) = try prepared()
        let damaged = Data("damaged".utf8)
        try damaged.write(to: file(root, "catalog.json"))
        let backup = try Data(contentsOf: file(root, "catalog.json.bak"))
        let candidate = try XCTUnwrap(store.recoveryCandidate())
        let failing = CatalogStore(directory: root, publication: .init { _, _, _, _ in throw POSIXError(.ENOSPC) })
        XCTAssertThrowsError(try failing.restoreBackup(candidate))
        XCTAssertEqual(try Data(contentsOf: file(root, "catalog.json")), damaged)
        XCTAssertEqual(try Data(contentsOf: file(root, "catalog.json.bak")), backup)
    }

    func testFreshDevCopiesTheMixedCatalogAndReadyDevIsNeverReimported() throws {
        let home = try SteamTestFixture.temporary(in: self).root
        let profile = AppDataProfile(home: home, isDevelopment: true)
        _ = try CatalogTestSupport.writeLegacy([CatalogTestSupport.completeLegacyGame()], to: profile.stableSupportRoot)
        let store = CatalogStore(directory: profile.stableSupportRoot)
        var mixed = try store.loadOrMigrate()
        mixed.games.append(.init(steam: SteamCatalogGame(appID: 10, name: "Steam game")))
        mixed = try store.save(mixed, expectedRevision: mixed.revision)
        let importer = DevelopmentProfileImporter()
        XCTAssertTrue(try importer.prepare(profile: profile, sourcePreferences: { [:] }, savePreferences: { _ in }))
        XCTAssertEqual(try CatalogStore(directory: profile.supportRoot).loadOrMigrate(), mixed)
        let sourceBytes = try Data(contentsOf: profile.stableSupportRoot.appendingPathComponent("catalog.json"))
        try Data("later source damage".utf8).write(to: profile.stableSupportRoot.appendingPathComponent("catalog.json"))
        XCTAssertFalse(try importer.prepare(profile: profile, sourcePreferences: { [:] }, savePreferences: { _ in XCTFail() }))
        XCTAssertEqual(try Data(contentsOf: profile.supportRoot.appendingPathComponent("catalog.json")), sourceBytes)
    }

    func testFreshDevRejectsUnsupportedOrMalformedCatalogBeforeActivation() throws {
        for bytes in [Data("{\"schemaVersion\":99}".utf8), Data("{\"valid_json_wrong_document\":true}".utf8)] {
            let profile = AppDataProfile(home: try SteamTestFixture.temporary(in: self).root, isDevelopment: true)
            try FileManager.default.createDirectory(at: profile.stableSupportRoot, withIntermediateDirectories: true)
            try bytes.write(to: profile.stableSupportRoot.appendingPathComponent("catalog.json"))
            XCTAssertThrowsError(try DevelopmentProfileImporter().prepare(profile: profile, sourcePreferences: { [:] }, savePreferences: { _ in XCTFail() }))
            XCTAssertFalse(FileManager.default.fileExists(atPath: profile.supportRoot.path))
        }
    }

    func testKeepCurrentLibraryArchivesBothVersionsWithoutMergingLegacyChanges() throws {
        let (root, store, original, _) = try prepared()
        var mixed = original
        mixed.games.append(.init(steam: SteamCatalogGame(appID: 10, name: "Arcane addition")))
        mixed = try store.save(mixed, expectedRevision: mixed.revision)
        let main = try Data(contentsOf: file(root, "catalog.json"))
        let backup = try Data(contentsOf: file(root, "catalog.json.bak"))
        let changed = try CatalogTestSupport.writeLegacy([], to: root)
        let legacyBackup = Data("legacy backup bytes".utf8)
        try legacyBackup.write(to: file(root, "library.json.bak"))
        XCTAssertThrowsError(try store.loadOrMigrate()) { XCTAssertEqual($0 as? CatalogStoreError, .legacyChanged) }
        let candidate = try XCTUnwrap(store.legacyConflictCandidate())
        XCTAssertEqual(try Data(contentsOf: file(root, "catalog.json")), main, "The offer does not modify either library")
        let kept = try store.keepCurrentLibrary(candidate)
        XCTAssertEqual(kept.games, mixed.games)
        XCTAssertEqual(kept.sources, mixed.sources)
        XCTAssertNotEqual(kept.revision, mixed.revision)
        XCTAssertEqual(try store.loadOrMigrate(), kept)
        let archive = try XCTUnwrap(conflictArchives(root).first)
        for (name, bytes) in [("catalog.json", main), ("catalog.json.bak", backup), ("library.json", changed), ("library.json.bak", legacyBackup)] {
            XCTAssertEqual(try Data(contentsOf: archive.appendingPathComponent(name)), bytes)
        }
        XCTAssertEqual(try Data(contentsOf: file(root, "library.json")), changed)
        XCTAssertEqual(try Data(contentsOf: file(root, "library.json.bak")), legacyBackup)
        XCTAssertNil(try store.legacyConflictCandidate())
        XCTAssertNoThrow(try store.save(kept, expectedRevision: kept.revision))
        XCTAssertThrowsError(try store.save(mixed, expectedRevision: mixed.revision))
    }

    func testStaleConflictCannotAcknowledgeLaterWritesToAnyInput() throws {
        for name in ["catalog.json", "catalog.json.bak", "library.json", "library.json.bak"] {
            let (root, store, _, _) = try prepared()
            _ = try CatalogTestSupport.writeLegacy([], to: root)
            let candidate = try XCTUnwrap(store.legacyConflictCandidate())
            let later = Data("later write".utf8)
            try later.write(to: file(root, name))
            let before = try Data(contentsOf: file(root, "catalog.json"))
            XCTAssertThrowsError(try store.keepCurrentLibrary(candidate)) { XCTAssertEqual($0 as? CatalogStoreError, .staleRevision) }
            XCTAssertEqual(try Data(contentsOf: file(root, name)), later)
            XCTAssertEqual(try Data(contentsOf: file(root, "catalog.json")), before)
            XCTAssertEqual(try conflictArchives(root).count, 0)
        }
    }

    func testAcceptedLegacyBaselineAlsoAppliesToTheRestorePoint() throws {
        let (root, store, original, _) = try prepared()
        _ = try CatalogTestSupport.writeLegacy([], to: root)
        let candidate = try XCTUnwrap(store.legacyConflictCandidate())
        let kept = try store.keepCurrentLibrary(candidate)
        try Data("damaged main".utf8).write(to: file(root, "catalog.json"))
        let recovery = try XCTUnwrap(store.recoveryCandidate())
        let restored = try store.restoreBackup(recovery)
        XCTAssertEqual(restored.games, original.games)
        XCTAssertEqual(restored.legacyOrigin, kept.legacyOrigin)
        XCTAssertEqual(try store.loadOrMigrate(), restored)
    }

    func testArchiveAndPublicationFailuresKeepCurrentAndLegacyBytes() throws {
        for failure in ["archive", "catalog.json", "archive sync"] {
            let (root, store, _, _) = try prepared()
            let changed = try CatalogTestSupport.writeLegacy([], to: root)
            let main = try Data(contentsOf: file(root, "catalog.json"))
            let candidate = try XCTUnwrap(store.legacyConflictCandidate())
            let failing = CatalogStore(directory: root, publication: .init(syncDirectory: { _ in
                if failure == "archive sync" { throw POSIXError(.ENOSPC) }
            }) { stage, target, replace, validate in
                if failure == "archive" || target == root.appendingPathComponent(failure) { throw POSIXError(.ENOSPC) }
                try CatalogPublication.atomic.publish(stage, target, replace, validate)
            })
            XCTAssertThrowsError(try failing.keepCurrentLibrary(candidate))
            XCTAssertEqual(try Data(contentsOf: file(root, "catalog.json")), main)
            XCTAssertEqual(try Data(contentsOf: file(root, "library.json")), changed)
            // A retry rechecks the actual backup too, rather than reusing a stale offer.
            XCTAssertNoThrow(try store.keepCurrentLibrary(XCTUnwrap(store.legacyConflictCandidate())))
        }
    }

    func testLegacyEditAtPublicationCannotBeAcknowledgedByAnOlderOffer() throws {
        let (root, store, _, _) = try prepared()
        let changed = try CatalogTestSupport.writeLegacy([], to: root)
        let candidate = try XCTUnwrap(store.legacyConflictCandidate())
        let main = try Data(contentsOf: file(root, "catalog.json"))
        let later = Data("an older app wrote again".utf8)
        let racing = CatalogStore(directory: root, publication: .init { stage, target, replace, validate in
            if target == root.appendingPathComponent("catalog.json") {
                try later.write(to: root.appendingPathComponent("library.json"))
            }
            try CatalogPublication.atomic.publish(stage, target, replace, validate)
        })
        XCTAssertThrowsError(try racing.keepCurrentLibrary(candidate))
        XCTAssertEqual(try Data(contentsOf: file(root, "catalog.json")), main)
        XCTAssertEqual(try Data(contentsOf: file(root, "library.json")), later)
        let archive = try XCTUnwrap(conflictArchives(root).first)
        XCTAssertEqual(try Data(contentsOf: archive.appendingPathComponent("library.json")), changed)
    }

    func testUnsafeLegacyInputNeverOffersAnAcknowledgement() throws {
        for name in ["library.json", "library.json.bak"] {
            let (root, store, _, _) = try prepared()
            _ = try CatalogTestSupport.writeLegacy([], to: root)
            try? FileManager.default.removeItem(at: file(root, name))
            try FileManager.default.createSymbolicLink(at: file(root, name), withDestinationURL: file(root, "catalog.json"))
            XCTAssertThrowsError(try store.legacyConflictCandidate())
        }
    }

    func testMissingAndBackupOnlyLegacyBaselinesCanBeAcceptedExplicitly() throws {
        for backupOnly in [false, true] {
            let (root, store, original, _) = try prepared()
            try FileManager.default.removeItem(at: file(root, "library.json"))
            if backupOnly { try Data("legacy backup".utf8).write(to: file(root, "library.json.bak")) }
            let candidate = try XCTUnwrap(store.legacyConflictCandidate())
            let kept = try store.keepCurrentLibrary(candidate)
            XCTAssertEqual(kept.legacyOrigin.kind, backupOnly ? .backup : .absent)
            XCTAssertEqual(kept.games, original.games)
            XCTAssertEqual(try store.loadOrMigrate(), kept)
            _ = try CatalogTestSupport.writeLegacy([], to: root)
            XCTAssertThrowsError(try store.loadOrMigrate())
            XCTAssertNotNil(try store.legacyConflictCandidate())
        }
    }

    private func conflictArchives(_ root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("catalog-conflict-") }
    }
}
