import XCTest
@testable import NXLibraryCore

final class NXNativeGameSettingsTests: XCTestCase {
    private let titleID = "040074A01BF12000"
    private let domain = "org.nxnative.040074a01bf12000"

    /// Bananza's list as the pinned engine packs it (no frame rate, language or render scale).
    private let launcherJSON = """
    {"schema":1,"game":"040074A01BF12000","settings":[
      {"env":"DM_OPMODE","kind":"choice","section":"Game","label":"Console mode","default":"1","level":"basic","options":[["1","Docked"],["0","Handheld"]]},
      {"env":"DM_PRESENT_UPSCALE","kind":"choice","section":"Game","label":"Upscaling","default":"off","options":[["off","Standard"],["metalfx","MetalFX"]]},
      {"env":"DM_FULLSCREEN","kind":"choice","section":"Game","label":"Display mode","default":"0","level":"basic","options":[["0","Window"],["1","Fullscreen"]]},
      {"env":"DM_RUMBLE","kind":"toggle","section":"Controls","label":"Game rumble","default":"1","level":"basic","on":"1","off":"0"},
      {"env":"DM_RUMBLE_GAIN","kind":"range","section":"Controls","label":"Rumble strength","default":"1.0","needs":"DM_RUMBLE=1","min":0.0,"max":3.0,"step":0.1},
      {"env":"DM_UPSCALER","kind":"choice","section":"Game","label":"Game's upscaler","default":"game","options":[["game","Game's own"],["metalfx","MetalFX"]]},
      {"env":"DM_METAL_HUD","kind":"toggle","section":"Performance","label":"Performance HUD","default":"0","on":"1","off":"0"}
    ]}
    """

    /// What NX Library 0.1.2 wrote for every game.
    private let oldEnv = """
    DM_FPS_TARGET=60
    DM_FULLSCREEN=1
    DM_LANG=it
    DM_METAL_HUD=1
    DM_OPMODE=1
    DM_PRESENT_UPSCALE=metalfx
    DM_RENDER_SCALE=1.00
    DM_RUMBLE=1
    DM_RUMBLE_GAIN=1

    """

    private struct Fixture {
        let game: PortedGame
        let support: URL
        let store: MemorySavedChoices
        let preferences: UserDefaults
        var envURL: URL { support.appendingPathComponent("040074A01BF12000/env.txt") }
    }

    private func fixture(dmSettings: Bool = true, env: String? = nil) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NXSettings-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Donkey Kong Bananza.app")
        let dm = app.appendingPathComponent("Contents/Resources/dm")
        try FileManager.default.createDirectory(at: dm, withIntermediateDirectories: true)
        try Data(launcherJSON.utf8).write(to: dm.appendingPathComponent("launcher.json"))
        var info: [String: Any] = ["CFBundleIdentifier": domain, "DMTitleID": titleID]
        if dmSettings { info["DMSettings"] = [["env": "DM_RUMBLE", "values": ["1", "0"]]] }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let support = root.appendingPathComponent("nxnative")
        if let env {
            try FileManager.default.createDirectory(at: support.appendingPathComponent(titleID),
                                                    withIntermediateDirectories: true)
            try Data(env.utf8).write(to: support.appendingPathComponent("\(titleID)/env.txt"))
        }
        let suite = "NXSettingsTests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        addTeardownBlock { preferences.removePersistentDomain(forName: suite) }
        let game = PortedGame(name: "Donkey Kong Bananza", url: app, platform: .macApp, sizeBytes: 1,
                              modificationDate: Date(), titleId: titleID)
        return Fixture(game: game, support: support, store: MemorySavedChoices(), preferences: preferences)
    }

    private func settings(_ f: Fixture) throws -> NXNativeGameSettings {
        try XCTUnwrap(NXNativeGameSettings.forGame(f.game, store: f.store, supportDirectory: f.support,
                                                   preferences: f.preferences))
    }

    func testLegacyBuildHasNoAdapter() throws {
        let f = try fixture(dmSettings: false, env: oldEnv)
        XCTAssertNil(NXNativeGameSettings.forGame(f.game, store: f.store, supportDirectory: f.support,
                                                  preferences: f.preferences))
        XCTAssertEqual(try String(contentsOf: f.envURL, encoding: .utf8), oldEnv, "a legacy build's env.txt is not touched")
    }

    func testMigrationMovesOfferedKeysAndKeepsTheRest() throws {
        let f = try fixture(env: "# mine\n" + oldEnv + "DM_SHADER_LOG=1\n")
        f.preferences.set(Data("{}".utf8), forKey: GameRuntimeConfig.storageKey(for: f.game))
        try settings(f).migrate()

        // Non-default offered values became saved choices; defaults left no key.
        XCTAssertEqual(f.store.values[domain], ["DM_FULLSCREEN": "1", "DM_METAL_HUD": "1",
                                                 "DM_PRESENT_UPSCALE": "metalfx"])
        // Lines the build does not offer, the player's own and comments stay, in order.
        XCTAssertEqual(try String(contentsOf: f.envURL, encoding: .utf8),
                       "# mine\nDM_FPS_TARGET=60\nDM_LANG=it\nDM_RENDER_SCALE=1.00\nDM_SHADER_LOG=1\n")
        XCTAssertNil(f.preferences.data(forKey: GameRuntimeConfig.storageKey(for: f.game)))

        // Idempotent.
        try settings(f).migrate()
        XCTAssertEqual(f.store.values[domain]?.count, 3)
    }

    func testEnvValueReplacesAnOlderSavedChoiceAndEmptyFileGoes() throws {
        let f = try fixture(env: "DM_OPMODE=0\nDM_RUMBLE=1\n")
        f.store.values[domain] = ["DM_OPMODE": "1", "DM_RUMBLE": "0"]
        try settings(f).migrate()
        XCTAssertEqual(f.store.values[domain], ["DM_OPMODE": "0"], "env.txt is what the game used: it wins")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.envURL.path))
    }

    func testValueTheBuildRefusesStaysInEnv() throws {
        let f = try fixture(env: "DM_RUMBLE_GAIN=7\n")
        try settings(f).migrate()
        XCTAssertEqual(try String(contentsOf: f.envURL, encoding: .utf8), "DM_RUMBLE_GAIN=7\n")
        XCTAssertNil(f.store.values[domain]?["DM_RUMBLE_GAIN"])
    }

    func testSnapshotOrderAndFixedKeys() throws {
        let f = try fixture(env: "DM_UPSCALER=metalfx\n")
        f.store.values[domain] = ["DM_RUMBLE": "0", "DM_OPMODE": "2"]
        let snapshot = try settings(f).snapshot()
        XCTAssertEqual(snapshot.value("DM_UPSCALER"), "metalfx", "a hand-written env.txt line wins")
        XCTAssertEqual(snapshot.fixed, ["DM_UPSCALER"])
        XCTAssertEqual(snapshot.value("DM_RUMBLE"), "0")
        XCTAssertEqual(snapshot.value("DM_OPMODE"), "1", "a saved value the build refuses reads as the default")
        XCTAssertFalse(snapshot.visible("DM_RUMBLE_GAIN"), "needs DM_RUMBLE=1")
        XCTAssertFalse(snapshot.isOffered("DM_FPS_TARGET"))
        XCTAssertEqual(try String(contentsOf: f.envURL, encoding: .utf8), "DM_UPSCALER=metalfx\n",
                       "an unmanaged key is never migrated")
    }

    func testSetWritesOnlyNonDefaultsAndRefusesUnofferedValues() throws {
        let f = try fixture()
        let s = try settings(f)
        try s.set("DM_RUMBLE_GAIN", to: "0.5")
        XCTAssertEqual(f.store.values[domain]?["DM_RUMBLE_GAIN"], "0.5")
        try s.set("DM_RUMBLE_GAIN", to: "1")
        XCTAssertNil(f.store.values[domain]?["DM_RUMBLE_GAIN"], "the default removes the key")
        XCTAssertThrowsError(try s.set("DM_OPMODE", to: "2"))
        XCTAssertThrowsError(try s.set("DM_FPS_TARGET", to: "60"))
    }

    func testApplyWritesOnlyChangedTypedFields() throws {
        let f = try fixture()
        f.store.values[domain] = ["DM_RUMBLE_GAIN": "0.5", "DM_UPSCALER": "metalfx"]
        let s = try settings(f)
        let base = s.runtimeConfig()
        XCTAssertEqual(base.rumbleGain, 1, "0.5 shows as the nearest whole strength")
        var review = base
        review.fullscreen = true
        try s.apply(review, changedFrom: base)
        XCTAssertEqual(f.store.values[domain], ["DM_RUMBLE_GAIN": "0.5", "DM_UPSCALER": "metalfx", "DM_FULLSCREEN": "1"],
                       "untouched fields keep values the typed config cannot show")

        try s.resetAll()
        XCTAssertEqual(f.store.values[domain] ?? [:], [:])
    }
}
