import XCTest
@testable import NXLibraryCore

final class CatalogPersonalizationTests: XCTestCase {
    func testPersonalKeySurvivesRenameOfATitleWithoutTitleID() throws {
        var payload = CatalogTestSupport.completeLegacyGame()
        payload.titleId = nil; payload.bundleId = nil; payload.name = "Old name"
        var entry = CatalogGame(nxnative: payload)
        payload.name = "New name"
        try entry.updateNXNative(payload)
        let context = CatalogPersonalizations(document: CatalogDocument(games: [entry]))
        XCTAssertEqual(context.nxnativeKey(for: payload), "Old name")
        XCTAssertEqual(CatalogPersonalizations.empty.nxnativeKey(for: payload), "New name", "Unpersisted previews retain their existing fallback")
    }

    func testSameTextKeyInDifferentIntegrationsCannotOverwritePersonalMetadata() throws {
        let root = try SteamTestFixture.temporary(in: self).root
        var payload = CatalogTestSupport.completeLegacyGame()
        payload.titleId = nil; payload.bundleId = "steam-10"
        let nx = CatalogGame(nxnative: payload).personalizationReference
        let steam = CatalogGame(steam: SteamCatalogGame(appID: 10, name: "Steam")).personalizationReference
        let nxStore = MetadataPicks(directory: nx.supportRoot(in: root))
        let steamStore = MetadataPicks(directory: steam.supportRoot(in: root))
        nxStore.set("Switch text", titleID: nx.key, field: .description)
        steamStore.set("Steam text", titleID: steam.key, field: .description)
        XCTAssertEqual(MetadataPicks(directory: root).value(titleID: "steam-10", field: .description), "Switch text")
        XCTAssertEqual(MetadataPicks(directory: steam.supportRoot(in: root)).value(titleID: "steam-10", field: .description), "Steam text")
        XCTAssertNotEqual(nx.supportRoot(in: root), steam.supportRoot(in: root))
    }
}
