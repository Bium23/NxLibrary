import XCTest
import Darwin
@testable import NXLibraryCore

final class CatalogStoreTests: XCTestCase {
    private func fixture() throws -> SteamTestFixture { try .temporary(in: self) }
    private func url(_ root: URL, _ name: String) -> URL { root.appendingPathComponent(name) }
    private func assertNoCatalog(_ root: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(FileManager.default.fileExists(atPath: url(root, "catalog.json").path), file: file, line: line)
    }

    func testMigrationPreservesAllLegacyFieldsKeysAndBytesAndIsNotRepeated() throws {
        let root = try fixture().root
        let original = CatalogTestSupport.completeLegacyGame()
        let bytes = try CatalogTestSupport.writeLegacy([original], to: root)
        let store = CatalogStore(directory: root)
        let migrated = try store.loadOrMigrate()
        XCTAssertEqual(migrated.games.map(\.nxnativeGame), [original])
        XCTAssertEqual(migrated.games[0].personalizationKey, "0100000000000001")
        XCTAssertEqual(migrated.source(.nxnative)?.isEnabled, true)
        XCTAssertEqual(migrated.source(.steam)?.isEnabled, false)
        var draft = migrated
        draft.games[0].setFavorite(false)
        let saved = try store.save(draft, expectedRevision: migrated.revision)
        XCTAssertNotEqual(saved.revision, migrated.revision)
        XCTAssertEqual(try store.loadOrMigrate(), saved)
        XCTAssertFalse(saved.games[0].isFavorite)
        XCTAssertEqual(try Data(contentsOf: url(root, "library.json")), bytes)
        XCTAssertEqual(try CatalogStore.decode(Data(contentsOf: url(root, "catalog.json.bak"))), migrated)
    }

    func testNewProfileDoesNotEnableAnIntegration() throws {
        let root = try fixture().root
        let result = try CatalogStore(directory: root).loadOrMigrate()
        XCTAssertTrue(result.games.isEmpty)
        XCTAssertEqual(Set(result.sources.map(\.integration)), [.steam, .nxnative])
        XCTAssertTrue(result.sources.allSatisfy { !$0.isEnabled })
        XCTAssertFalse(FileManager.default.fileExists(atPath: url(root, "library.json").path))
        XCTAssertEqual(try CatalogStore.decode(Data(contentsOf: url(root, "catalog.json.bak"))), result)
    }

    func testOnlyAbsentLegacyMainAllowsItsValidBackup() throws {
        let root = try fixture().root
        let original = CatalogTestSupport.completeLegacyGame()
        let bytes = try CatalogTestSupport.writeLegacy([original], to: root)
        try FileManager.default.moveItem(at: url(root, "library.json"), to: url(root, "library.json.bak"))
        let store = CatalogStore(directory: root)
        let result = try store.loadOrMigrate()
        XCTAssertEqual(result.games.first?.nxnativeGame, original)
        XCTAssertEqual(try Data(contentsOf: url(root, "library.json.bak")), bytes)
        try bytes.write(to: url(root, "library.json"))
        XCTAssertThrowsError(try store.loadOrMigrate()) { XCTAssertEqual($0 as? CatalogStoreError, .legacyChanged) }
    }

    func testCorruptLegacyMainDoesNotSilentlyUseGoodBackup() throws {
        let root = try fixture().root
        let bytes = try CatalogTestSupport.writeLegacy([CatalogTestSupport.completeLegacyGame()], to: root)
        try bytes.write(to: url(root, "library.json.bak"))
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: url(root, "library.json"))
        XCTAssertThrowsError(try CatalogStore(directory: root).loadOrMigrate())
        assertNoCatalog(root)
        XCTAssertEqual(try Data(contentsOf: url(root, "library.json")), corrupt)
        XCTAssertEqual(try Data(contentsOf: url(root, "library.json.bak")), bytes)
    }

    func testUnknownLegacySchemaAndDuplicateUUIDsAreRejected() throws {
        for (schema, count) in [(99, 1), (1, 2)] {
            let root = try fixture().root
            let bytes = try CatalogTestSupport.writeLegacy(Array(repeating: CatalogTestSupport.completeLegacyGame(), count: count), to: root, schemaVersion: schema)
            XCTAssertThrowsError(try CatalogStore(directory: root).loadOrMigrate())
            assertNoCatalog(root)
            XCTAssertEqual(try Data(contentsOf: url(root, "library.json")), bytes)
        }
    }

    func testLegacySymlinkAndFIFOAreRejectedWithoutFollowingOrBlocking() throws {
        for special in ["symlink", "fifo"] {
            let root = try fixture().root
            let target = url(root, "library.json")
            if special == "symlink" {
                let external = url(root, "external.json")
                try Data("untouched".utf8).write(to: external)
                try FileManager.default.createSymbolicLink(at: target, withDestinationURL: external)
            } else { XCTAssertEqual(mkfifo(target.path, 0o600), 0) }
            XCTAssertThrowsError(try CatalogStore(directory: root).loadOrMigrate())
            assertNoCatalog(root)
        }
    }

    func testOversizedLegacyFileIsRejected() throws {
        let root = try fixture().root
        try Data(repeating: 0x20, count: 16 * 1024 * 1024 + 1).write(to: url(root, "library.json"))
        XCTAssertThrowsError(try CatalogStore(directory: root).loadOrMigrate())
        assertNoCatalog(root)
    }

    func testChangedLegacyMainBlocksReadsAndWritesButBackupRotationDoesNot() throws {
        let root = try fixture().root
        let bytes = try CatalogTestSupport.writeLegacy([CatalogTestSupport.completeLegacyGame()], to: root)
        let store = CatalogStore(directory: root)
        let first = try store.loadOrMigrate()
        try Data("an obsolete backup".utf8).write(to: url(root, "library.json.bak"))
        XCTAssertEqual(try store.loadOrMigrate(), first)
        try (bytes + Data(" ".utf8)).write(to: url(root, "library.json"))
        XCTAssertThrowsError(try store.loadOrMigrate()) { XCTAssertEqual($0 as? CatalogStoreError, .legacyChanged) }
        XCTAssertThrowsError(try store.save(first, expectedRevision: first.revision))
        XCTAssertEqual(try CatalogStore.decode(Data(contentsOf: url(root, "catalog.json"))), first)
    }

    func testNewLegacyFileAfterEmptyMigrationCannotBeIgnored() throws {
        let root = try fixture().root
        let store = CatalogStore(directory: root)
        _ = try store.loadOrMigrate()
        _ = try CatalogTestSupport.writeLegacy([], to: root)
        XCTAssertThrowsError(try store.loadOrMigrate()) { XCTAssertEqual($0 as? CatalogStoreError, .legacyChanged) }
    }

    func testTwoStoresCannotSaveTheSameRevisionTwice() throws {
        let root = try fixture().root
        _ = try CatalogTestSupport.writeLegacy([CatalogTestSupport.completeLegacyGame()], to: root)
        let a = CatalogStore(directory: root), b = CatalogStore(directory: root)
        let old = try a.loadOrMigrate()
        var draft = old
        draft.games[0].setHidden(false)
        let committed = try a.save(draft, expectedRevision: old.revision)
        XCTAssertThrowsError(try b.save(old, expectedRevision: old.revision)) { XCTAssertEqual($0 as? CatalogStoreError, .staleRevision) }
        XCTAssertEqual(try b.loadOrMigrate(), committed)
    }

    func testAWriterHoldingTheLockRefusesAnotherWriterInsteadOfWaiting() throws {
        let root = try fixture().root
        let store = CatalogStore(directory: root)
        let initial = try store.loadOrMigrate()
        let competing = CatalogStore(directory: root, publication: .init { staged, target, replace, validate in
            XCTAssertThrowsError(try store.loadOrMigrate()) { XCTAssertEqual($0 as? CatalogStoreError, .busy) }
            try CatalogPublication.atomic.publish(staged, target, replace, validate)
        })
        _ = try competing.save(initial, expectedRevision: initial.revision)
    }

    func testPublicationFailurePreservesReadableMainBackupAndLegacyBytes() throws {
        let root = try fixture().root
        let bytes = try CatalogTestSupport.writeLegacy([CatalogTestSupport.completeLegacyGame()], to: root)
        let initial = try CatalogStore(directory: root).loadOrMigrate()
        let failing = CatalogStore(directory: root, publication: .init { _, _, _, _ in throw POSIXError(.ENOSPC) })
        XCTAssertThrowsError(try failing.save(initial, expectedRevision: initial.revision))
        XCTAssertEqual(try CatalogStore(directory: root).loadOrMigrate(), initial)
        XCTAssertEqual(try CatalogStore.decode(Data(contentsOf: url(root, "catalog.json.bak"))), initial)
        XCTAssertEqual(try Data(contentsOf: url(root, "library.json")), bytes)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".catalog-stage-") })
    }

    func testLegacyChangeDuringPublicationRejectsThePreparedCandidate() throws {
        let root = try fixture().root
        let legacy = try CatalogTestSupport.writeLegacy([CatalogTestSupport.completeLegacyGame()], to: root)
        let initial = try CatalogStore(directory: root).loadOrMigrate()
        let changing = CatalogStore(directory: root, publication: .init { staged, target, replace, validate in
            try (legacy + Data(" ".utf8)).write(to: self.url(root, "library.json"))
            try CatalogPublication.atomic.publish(staged, target, replace, validate)
        })
        XCTAssertThrowsError(try changing.save(initial, expectedRevision: initial.revision))
        XCTAssertEqual(try CatalogStore.decode(Data(contentsOf: url(root, "catalog.json"))), initial)
    }

    func testDamagedOrUnsupportedCatalogNeverActivatesEmptyOrOverwritesGoodBackup() throws {
        for replacement in [Data("broken".utf8), Data("{\"schemaVersion\":99}".utf8)] {
            let root = try fixture().root
            let store = CatalogStore(directory: root)
            let initial = try store.loadOrMigrate()
            let backup = try Data(contentsOf: url(root, "catalog.json.bak"))
            try replacement.write(to: url(root, "catalog.json"))
            XCTAssertThrowsError(try store.loadOrMigrate()) { XCTAssertEqual($0 as? CatalogStoreError, .invalidCatalog(backupAvailable: true)) }
            XCTAssertThrowsError(try store.save(initial, expectedRevision: initial.revision))
            XCTAssertEqual(try Data(contentsOf: url(root, "catalog.json.bak")), backup)
            XCTAssertEqual(try Data(contentsOf: url(root, "catalog.json")), replacement)
        }
    }

    func testMissingCatalogWithValidBackupRequiresRecoveryRatherThanNewMigration() throws {
        let root = try fixture().root
        let store = CatalogStore(directory: root)
        _ = try store.loadOrMigrate()
        try FileManager.default.removeItem(at: url(root, "catalog.json"))
        XCTAssertThrowsError(try store.loadOrMigrate()) { XCTAssertEqual($0 as? CatalogStoreError, .invalidCatalog(backupAvailable: true)) }
        assertNoCatalog(root)
    }

    func testInvalidDraftCannotReplaceTheValidCatalog() throws {
        let root = try fixture().root
        _ = try CatalogTestSupport.writeLegacy([CatalogTestSupport.completeLegacyGame()], to: root)
        let store = CatalogStore(directory: root)
        let initial = try store.loadOrMigrate()
        var duplicate = initial
        duplicate.games.append(initial.games[0])
        XCTAssertThrowsError(try store.save(duplicate, expectedRevision: initial.revision))
        var invalidSource = initial
        invalidSource.sources = [.init(integration: .steam, isEnabled: true)]
        XCTAssertThrowsError(try store.save(invalidSource, expectedRevision: initial.revision))
        XCTAssertEqual(try store.loadOrMigrate(), initial)
    }

    func testFractionalDatesSurviveNewCatalogWrites() throws {
        let root = try fixture().root
        let store = CatalogStore(directory: root)
        var draft = try store.loadOrMigrate()
        var legacy = CatalogTestSupport.completeLegacyGame()
        legacy.modificationDate = Date(timeIntervalSinceReferenceDate: 12345.678901)
        draft.games = [.init(nxnative: legacy)]
        let saved = try store.save(draft, expectedRevision: draft.revision)
        XCTAssertEqual(try store.loadOrMigrate().games[0].nxnativeGame?.modificationDate, legacy.modificationDate)
        XCTAssertEqual(saved.games[0].nxnativeGame, legacy)
    }
    func testFinalDirectorySyncFailureReportsUncertainCommitAndAllowsExplicitReload() throws {
        let root = try fixture().root
        _ = try CatalogTestSupport.writeLegacy([CatalogTestSupport.completeLegacyGame()], to: root)
        let store = CatalogStore(directory: root)
        let initial = try store.loadOrMigrate()
        var draft = initial
        draft.games[0].setFavorite(false)
        let failing = CatalogStore(directory: root, publication: .init(syncDirectory: { _ in throw POSIXError(.EIO) },
                                                                      publish: CatalogPublication.atomic.publish))
        XCTAssertThrowsError(try failing.save(draft, expectedRevision: initial.revision)) {
            XCTAssertEqual($0 as? CatalogStoreError, .commitUncertain)
        }
        // Publication already happened; the caller must reload, not assume
        // the old revision still owns the file or retry as an empty library.
        let reloaded = try store.loadOrMigrate()
        XCTAssertNotEqual(reloaded.revision, initial.revision)
        XCTAssertFalse(reloaded.games[0].isFavorite)
        XCTAssertEqual(try CatalogStore.decode(Data(contentsOf: url(root, "catalog.json.bak"))), initial)
        XCTAssertThrowsError(try store.save(draft, expectedRevision: initial.revision)) {
            XCTAssertEqual($0 as? CatalogStoreError, .staleRevision)
        }
    }

}
