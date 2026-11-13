import XCTest
@testable import NXLibraryCore

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
}
