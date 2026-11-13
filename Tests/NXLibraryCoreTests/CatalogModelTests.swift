import XCTest
@testable import NXLibraryCore

final class CatalogModelTests: XCTestCase {
    func testCompleteLegacyRecordRoundTripsWithoutLosingAnyField() throws {
        let original = CatalogTestSupport.completeLegacyGame()
        let game = CatalogGame(nxnative: original)
        XCTAssertEqual(game.id, original.id)
        XCTAssertEqual(game.nxnativeGame, original)
        XCTAssertEqual(game.personalizationKey, "0100000000000001")
        let data = try JSONEncoder().encode(game)
        let loaded = try JSONDecoder().decode(CatalogGame.self, from: data)
        XCTAssertEqual(loaded, game)
        XCTAssertEqual(loaded.nxnativeGame, original)
        XCTAssertNil(loaded.steamGame)
    }

    func testLegacyKeyFallbackAndProviderNamespacesRemainDistinct() throws {
        var legacy = CatalogTestSupport.completeLegacyGame()
        legacy.titleId = nil
        legacy.bundleId = "fixture.bundle"
        let game = CatalogGame(nxnative: legacy)
        XCTAssertEqual(game.personalizationKey, "fixture.bundle")
        let steam = CatalogGame(steam: SteamCatalogGame(appID: 10, name: "Same name"))
        XCTAssertNotEqual(game.personalizationReference.namespace, steam.personalizationReference.namespace)
        XCTAssertNotEqual(game.providerIdentity, steam.providerIdentity)
        XCTAssertNil(steam.nxnativeGame)
    }

    func testCommonUserStateHasOneOwnerAndSurvivesSerialization() throws {
        var game = CatalogGame(nxnative: CatalogTestSupport.completeLegacyGame())
        game.setFavorite(false)
        game.setHidden(false)
        XCTAssertFalse(try XCTUnwrap(game.nxnativeGame).isFavorite)
        XCTAssertFalse(try XCTUnwrap(game.nxnativeGame).isHidden)
        var steam = CatalogGame(steam: SteamCatalogGame(appID: 10, name: "G"))
        steam.setFavorite(true)
        steam.setHidden(true)
        let result = try JSONDecoder().decode(CatalogGame.self, from: JSONEncoder().encode(steam))
        XCTAssertTrue(result.isFavorite)
        XCTAssertTrue(result.isHidden)
        XCTAssertEqual(result.id, steam.id)
    }

    func testUpdatesRejectIntegrationOrIdentityChangesAndKeepPersonalLookupReference() throws {
        let original = CatalogTestSupport.completeLegacyGame()
        var game = CatalogGame(nxnative: original)
        var update = original
        update.titleId = "0100000000000002"
        try game.updateNXNative(update)
        XCTAssertEqual(game.personalizationKey, "0100000000000001")
        XCTAssertEqual(game.nxnativeGame?.titleId, "0100000000000002")
        update.id = UUID()
        XCTAssertThrowsError(try game.updateNXNative(update))
        var steam = CatalogGame(steam: SteamCatalogGame(appID: 10, name: "G"))
        XCTAssertThrowsError(try steam.updateNXNative(original))
        XCTAssertNil(steam.nxnativeGame)
    }

    func testSteamDoesNotSupportEngineOrDestructiveOperations() throws {
        let game = CatalogGame(steam: SteamCatalogGame(appID: 10, name: "Steam game"))
        let shown = CatalogGamePresentation(game: game, sourceEnabled: true)
        for operation: CatalogGameOperation in [.build, .writeRuntimeSettings, .manageSaves, .manageMods, .manageCheats,
                                               .writeAppIcon, .deleteInstalledFiles, .manageBuildInputs] {
            XCTAssertThrowsError(try shown.requireSupported(operation))
        }
        XCTAssertNoThrow(try shown.requireSupported(.customizeArtwork))
        XCTAssertNoThrow(try shown.requireSupported(.favorite))
        XCTAssertNoThrow(try shown.requireSupported(.openSourceClient))
        XCTAssertNil(shown.launchTarget)
        XCTAssertFalse(shown.isListedNormally)
    }

    func testLegacyPresentationPreservesPlaySemanticsWithoutConsultingTheFilesystem() throws {
        var original = CatalogTestSupport.completeLegacyGame()
        original.isHidden = false
        let shown = CatalogGamePresentation(game: CatalogGame(nxnative: original), sourceEnabled: true)
        XCTAssertEqual(shown.launchTarget, .nxnative(appURL: original.url))
        XCTAssertTrue(shown.isListedNormally)
        XCTAssertEqual(shown.installations.first?.contentURL, original.url)
        original.status = .appMissing
        XCTAssertNil(CatalogGamePresentation(game: CatalogGame(nxnative: original), sourceEnabled: true).launchTarget)
        original.status = .notBuilt
        original.url = URL(fileURLWithPath: "/tmp/catalog-fixture/workspace")
        XCTAssertTrue(CatalogGamePresentation(game: CatalogGame(nxnative: original), sourceEnabled: true).installations.isEmpty)
    }

    func testUnknownIntegrationTagCannotBeDecodedAsAnEmptyOrLegacyGame() throws {
        let game = CatalogGame(nxnative: CatalogTestSupport.completeLegacyGame())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as? [String: Any])
        json["integration"] = "unknown-future-source"
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try JSONDecoder().decode(CatalogGame.self, from: data))
    }
}
