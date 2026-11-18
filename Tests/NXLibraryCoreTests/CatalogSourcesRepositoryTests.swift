import XCTest
@testable import NXLibraryCore

final class CatalogSourcesRepositoryTests: XCTestCase {
    private func prepared() throws -> (SteamTestFixture, CatalogRepository) {
        let fixture = try SteamTestFixture.temporary(in: self)
        _ = try CatalogTestSupport.writeLegacy([CatalogTestSupport.completeLegacyGame()], to: fixture.root)
        return (fixture, CatalogRepository(store: CatalogStore(directory: fixture.root)))
    }
    private func snapshot(_ root: URL) -> SteamLibrarySnapshot {
        let content = root.appendingPathComponent("steamapps/common/Fixture")
        let app = content.appendingPathComponent("Fixture.app")
        let native = NativeMacApplication(url: app, executableURL: app.appendingPathComponent("Contents/MacOS/game"),
                                          bundleIdentifier: "test.steam", name: "Fixture Steam", architectures: [.arm64],
                                          isDeclaredGame: true, fileObservations: [])
        return .init(libraries: [.init(root: root, isReadable: true, isComplete: true)],
                     games: [.init(appID: 10, name: "Fixture Steam", installationURL: content, libraryURL: root,
                                   reportedSizeBytes: 200, buildID: "1", nativeApps: [native], state: .nativeReady)], issues: [])
    }

    func testOldSchemaOneWithoutSourceGenerationDecodesDeterministically() throws {
        let (_, repository) = try prepared()
        let document = try repository.load()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        var sources = try XCTUnwrap(json["sources"] as? [[String: Any]])
        for index in sources.indices { sources[index].removeValue(forKey: "generation") }
        json["sources"] = sources
        let old = try JSONSerialization.data(withJSONObject: json)
        let a = try CatalogStore.decode(old), b = try CatalogStore.decode(old)
        XCTAssertEqual(a, b)
        XCTAssertEqual(try CatalogStore.decode(JSONEncoder().encode(a)), a)
        XCTAssertEqual(a.games, document.games)
    }

    func testPersonalEditsDuringAScanArePreservedWhenSnapshotCommits() throws {
        let (fixture, repository) = try prepared()
        let enabled = try repository.configureSource(.steam, enabled: true, root: fixture.root)
        let source = try XCTUnwrap(enabled.source(.steam))
        _ = try repository.setFavorite(false, for: enabled.games[0].id)
        let merged = try repository.applySteam(snapshot(fixture.root), expectedSource: source)
        XCTAssertFalse(merged.games[0].isFavorite)
        XCTAssertEqual(merged.games.count, 2)
        XCTAssertEqual(merged.games[1].steamGame?.appID, 10)
        let id = merged.games[1].id
        _ = try repository.setFavorite(true, for: id)
        _ = try repository.setHidden(true, for: id)
        let again = try repository.applySteam(snapshot(fixture.root), expectedSource: source)
        XCTAssertEqual(again.games[1].id, id)
        XCTAssertTrue(again.games[1].isFavorite); XCTAssertTrue(again.games[1].isHidden)
    }

    func testDisableReenableAtSameRootInvalidatesOlderSourceGeneration() throws {
        let (fixture, repository) = try prepared()
        let initial = try repository.configureSource(.steam, enabled: true, root: fixture.root)
        let old = try XCTUnwrap(initial.source(.steam))
        _ = try repository.configureSource(.steam, enabled: false, root: fixture.root)
        let enabled = try repository.configureSource(.steam, enabled: true, root: fixture.root)
        XCTAssertNotEqual(enabled.source(.steam)?.generation, old.generation)
        XCTAssertThrowsError(try repository.applySteam(snapshot(fixture.root), expectedSource: old))
        XCTAssertEqual(try repository.load(), enabled)
    }

    func testChangingRootOrDisablingNeverAppliesOldSnapshot() throws {
        let (fixture, repository) = try prepared()
        let initial = try repository.configureSource(.steam, enabled: true, root: fixture.root)
        let source = try XCTUnwrap(initial.source(.steam))
        _ = try repository.configureSource(.steam, enabled: true, root: fixture.root.appendingPathComponent("Other"))
        XCTAssertThrowsError(try repository.applySteam(snapshot(fixture.root), expectedSource: source))
        _ = try repository.configureSource(.steam, enabled: false, root: fixture.root)
        XCTAssertThrowsError(try repository.applySteam(snapshot(fixture.root), expectedSource: source))
        XCTAssertEqual(try repository.load().games.count, 1)
    }
    func testExplicitNXAdoptionEnablesItsExperienceWhilePassiveScanStaysDisabled() throws {
        let root = try SteamTestFixture.temporary(in: self).root
        let repository = CatalogRepository(store: CatalogStore(directory: root))
        let game = CatalogTestSupport.completeLegacyGame()
        XCTAssertFalse(try repository.load().source(.nxnative)!.isEnabled)
        XCTAssertThrowsError(try repository.mergeNXNative(scanned: [game]))
        let adopted = try repository.mergeNXNative(scanned: [game], enableSource: true)
        XCTAssertTrue(adopted.source(.nxnative)!.isEnabled)
        XCTAssertEqual(adopted.games.first?.id, game.id)
        XCTAssertFalse(adopted.source(.steam)!.isEnabled)
    }

    func testRepeatedFavoriteCommandUsesLatestPersistedValue() throws {
        let (fixture, repository) = try prepared()
        let enabled = try repository.configureSource(.steam, enabled: true, root: fixture.root)
        let scanned = try repository.applySteam(snapshot(fixture.root), expectedSource: enabled.source(.steam)!)
        let captured = try XCTUnwrap(scanned.games.first { $0.integration == .steam })
        XCTAssertFalse(captured.isFavorite)
        // The keyboard can retain one Details view/ID across both commands.
        let favorite = try repository.toggleFavorite(for: captured.id)
        XCTAssertTrue(favorite.games.first { $0.id == captured.id }!.isFavorite)
        let unfavorite = try repository.toggleFavorite(for: captured.id)
        XCTAssertFalse(unfavorite.games.first { $0.id == captured.id }!.isFavorite)
        XCTAssertEqual(try repository.load(), unfavorite)
        XCTAssertEqual(unfavorite.source(.steam), scanned.source(.steam))
    }

}
