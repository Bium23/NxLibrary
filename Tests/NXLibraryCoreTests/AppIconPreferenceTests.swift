import XCTest
@testable import NXLibraryCore

final class AppIconPreferenceTests: XCTestCase {
    private func game() -> PortedGame {
        PortedGame(name: "Game", url: URL(fileURLWithPath: "/tmp/Game.app"), platform: .macApp,
                   sizeBytes: 1, modificationDate: Date(timeIntervalSince1970: 0))
    }

    func testAutomaticPreservesBothExplicitDestinationsAcrossRebuildAndRelaunch() throws {
        for onMac in [true, false] {
            var g = game()
            g.appIconOnMac = onMac
            g.usesPickedAppIcon = onMac
            g.useAutomaticAppIcon()
            g.recordInstalledBuild(BuildRecord(), toolchain: ToolchainInfo(), at: g.url, version: "2.0", date: Date())
            let restored = try JSONDecoder().decode(PortedGame.self, from: JSONEncoder().encode(g))
            XCTAssertEqual(restored.appIconOnMac, onMac)
            XCTAssertEqual(restored.wantsAutomaticAppIcon(hasPick: false, hasOriginalIcon: false), onMac)
            XCTAssertFalse(restored.usesPickedAppIcon)
            XCTAssertTrue(restored.appIconPending)
        }
    }

    func testAutomaticRetainsLegacyMacOptInWithoutOverridingExplicitOnlyHere() {
        var legacy = game()
        legacy.usesPickedAppIcon = true
        legacy.useAutomaticAppIcon()
        XCTAssertEqual(legacy.appIconOnMac, true)
        XCTAssertFalse(legacy.usesPickedAppIcon)

        legacy.appIconOnMac = false
        legacy.usesPickedAppIcon = true
        legacy.useAutomaticAppIcon()
        XCTAssertEqual(legacy.appIconOnMac, false)
    }

    func testOnlyHereOverridesAutomaticIconForAnAppWithNoOriginalIcon() {
        var g = game()
        g.appIconOnMac = false
        XCTAssertFalse(g.wantsPickedAppIcon(hasPick: true, hasOriginalIcon: false))
        XCTAssertFalse(g.wantsPickedAppIcon(hasPick: true, hasOriginalIcon: true))
    }

    func testUseOnMacRequiresAnArtworkPickAndSurvivesRebuilds() throws {
        var g = game()
        g.appIconOnMac = true
        g.recordInstalledBuild(BuildRecord(), toolchain: ToolchainInfo(), at: g.url, version: "2.0", date: Date())
        let restored = try JSONDecoder().decode(PortedGame.self, from: JSONEncoder().encode(g))
        XCTAssertTrue(restored.wantsPickedAppIcon(hasPick: true, hasOriginalIcon: false))
        XCTAssertTrue(restored.wantsPickedAppIcon(hasPick: true, hasOriginalIcon: true))
        XCTAssertFalse(restored.wantsPickedAppIcon(hasPick: false, hasOriginalIcon: false))
    }

    func testExplicitOnlyHerePersistsAcrossRelaunchAndOverridesLegacyTrue() throws {
        var g = game()
        g.usesPickedAppIcon = true
        g.appIconOnMac = false
        g.recordInstalledBuild(BuildRecord(), toolchain: ToolchainInfo(), at: g.url, version: "2.0", date: Date())
        let restored = try JSONDecoder().decode(PortedGame.self, from: JSONEncoder().encode(g))
        XCTAssertEqual(restored.appIconOnMac, false)
        XCTAssertFalse(restored.wantsPickedAppIcon(hasPick: true, hasOriginalIcon: false))
    }

    func testLibraryRescanPreservesOnlyHereRatherThanTakingScannedDefaults() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryStore(directory: dir)
        var saved = game()
        saved.appIconOnMac = false
        try store.save(LibraryFile(games: [saved]))
        let merged = try XCTUnwrap(try store.merge(scanned: [game()]).games.first)
        XCTAssertEqual(merged.appIconOnMac, false)
        XCTAssertFalse(merged.wantsPickedAppIcon(hasPick: true, hasOriginalIcon: false))
    }

    func testAutomaticFallbackNeverOverridesAPickOriginalIconOrOnlyHere() {
        var g = game()
        XCTAssertTrue(g.wantsAutomaticAppIcon(hasPick: false, hasOriginalIcon: false))
        XCTAssertFalse(g.wantsAutomaticAppIcon(hasPick: true, hasOriginalIcon: false))
        XCTAssertFalse(g.wantsAutomaticAppIcon(hasPick: false, hasOriginalIcon: true))
        g.appIconOnMac = false
        XCTAssertFalse(g.wantsAutomaticAppIcon(hasPick: false, hasOriginalIcon: false))
    }

    func testOlderLibrariesKeepTheirBehaviorUntilThePlayerMakesAChoice() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(game())) as? [String: Any])
        json.removeValue(forKey: "appIconOnMac")
        let old = try JSONDecoder().decode(PortedGame.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.appIconOnMac)
        XCTAssertTrue(old.wantsPickedAppIcon(hasPick: true, hasOriginalIcon: false))
        XCTAssertFalse(old.wantsPickedAppIcon(hasPick: true, hasOriginalIcon: true))
        var optedIn = old
        optedIn.usesPickedAppIcon = true
        XCTAssertTrue(optedIn.wantsPickedAppIcon(hasPick: true, hasOriginalIcon: true))
    }
}
