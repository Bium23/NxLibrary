import XCTest
@testable import NXLibraryCore

final class DevelopmentProfileTests: XCTestCase {
    private func fixture() throws -> (URL, AppDataProfile) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("NXProfile-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return (home, AppDataProfile(home: home, isDevelopment: true))
    }
    private func put(_ data: String, _ name: String, profile: AppDataProfile) throws {
        let file = profile.stableSupportRoot.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(data.utf8).write(to: file)
    }
    func testBuildIdentityMustSelectExactlyOneMatchingProfile() throws {
        XCTAssertNoThrow(try AppData.validateBuildIdentity(["CFBundleIdentifier": "local.nxlibrary", "NXLibraryRelease": true]))
        XCTAssertNoThrow(try AppData.validateBuildIdentity(["CFBundleIdentifier": "local.nxlibrary.development", "NXLibraryDevelopmentProfile": true]))
        for invalid: [String: Any] in [[:], ["CFBundleIdentifier": "local.nxlibrary.development"],
                                     ["CFBundleIdentifier": "local.nxlibrary", "NXLibraryDevelopmentProfile": true],
                                     ["CFBundleIdentifier": "local.nxlibrary.development", "NXLibraryRelease": true],
                                     ["CFBundleIdentifier": "local.nxlibrary", "NXLibraryRelease": true, "NXLibraryDevelopmentProfile": true]] {
            XCTAssertThrowsError(try AppData.validateBuildIdentity(invalid))
        }
    }
    func testProfileSeparatesSupportCachesAndPreferenceDomain() throws {
        let (home, dev) = try fixture()
        let stable = AppDataProfile(home: home, isDevelopment: false)
        XCTAssertNotEqual(dev.supportRoot, stable.supportRoot)
        XCTAssertNotEqual(dev.cacheRoot, stable.cacheRoot)
        XCTAssertNotEqual(dev.preferencesDomain, stable.preferencesDomain)
        XCTAssertEqual(stable.supportRoot, dev.stableSupportRoot)
    }
    func testCopiesOnlyLauncherDataAndPreservesSourceAndIdentity() throws {
        let (_, profile) = try fixture()
        let id = UUID()
        let game = PortedGame(id: id, name: "Personal game", url: URL(fileURLWithPath: "/Applications/Game.app"), platform: .macApp, sizeBytes: 1, modificationDate: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(LibraryFile(games: [game]))
        try FileManager.default.createDirectory(at: profile.stableSupportRoot, withIntermediateDirectories: true)
        try encoded.write(to: profile.stableSupportRoot.appendingPathComponent("library.json"))
        try put("{}", "settings.json", profile: profile)
        try put("personal", "artwork-picks/own.png", profile: profile)
        try put("do not copy", "keys/prod.keys", profile: profile)
        try put("do not copy", "workspaces/game_build/content", profile: profile)
        try put("do not copy", "steamgriddb-api-key", profile: profile)
        var saved: [String: Any] = [:]
        let importer = DevelopmentProfileImporter()
        XCTAssertTrue(try importer.prepare(profile: profile, sourcePreferences: { ["NXLibrary_SetupCompleted": true, "NXNative_GameConfig_game": Data([1]), "AppleLanguages": ["en"], "NXLibrary_AuthToken": "synthetic"] }, savePreferences: { saved = $0 }))
        XCTAssertEqual(saved["NXLibrary_SetupCompleted"] as? Bool, true)
        XCTAssertNil(saved["AppleLanguages"])
        XCTAssertNil(saved["NXLibrary_AuthToken"])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let copied = try decoder.decode(LibraryFile.self, from: Data(contentsOf: profile.supportRoot.appendingPathComponent("library.json")))
        XCTAssertEqual(copied.games.first?.id, id)
        XCTAssertEqual(copied.games.first?.url, game.url)
        XCTAssertEqual(try Data(contentsOf: profile.stableSupportRoot.appendingPathComponent("library.json")), encoded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.supportRoot.appendingPathComponent("keys").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.supportRoot.appendingPathComponent("workspaces").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.supportRoot.appendingPathComponent("steamgriddb-api-key").path))
    }
    func testSecondImportDoesNotOverwriteDevelopmentChanges() throws {
        let (_, profile) = try fixture()
        try put("{}", "settings.json", profile: profile)
        let importer = DevelopmentProfileImporter()
        _ = try importer.prepare(profile: profile, sourcePreferences: { [:] }, savePreferences: { _ in })
        let file = profile.supportRoot.appendingPathComponent("settings.json")
        try Data(#"{"showClock":false}"#.utf8).write(to: file)
        XCTAssertFalse(try importer.prepare(profile: profile, sourcePreferences: { XCTFail("must not reread source preferences"); return [:] }, savePreferences: { _ in XCTFail("must not reimport preferences") }))
        XCTAssertEqual(try String(contentsOf: file), #"{"showClock":false}"#)
    }
    func testMalformedSourceIsNotRepairedOrActivated() throws {
        let (_, profile) = try fixture()
        try put("broken", "library.json", profile: profile)
        XCTAssertThrowsError(try DevelopmentProfileImporter().prepare(profile: profile, sourcePreferences: { [:] }, savePreferences: { _ in XCTFail() }))
        XCTAssertEqual(try String(contentsOf: profile.stableSupportRoot.appendingPathComponent("library.json")), "broken")
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.supportRoot.path))
    }
    func testSymlinkDoesNotCopyExternalGameData() throws {
        let (home, profile) = try fixture()
        let external = home.appendingPathComponent("actual-game")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profile.stableSupportRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: profile.stableSupportRoot.appendingPathComponent("artwork-picks"), withDestinationURL: external)
        XCTAssertThrowsError(try DevelopmentProfileImporter().prepare(profile: profile, sourcePreferences: { [:] }, savePreferences: { _ in }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.supportRoot.path))
    }
    func testPreferenceFailureCanResumeWithoutOverwritingSource() throws {
        let (_, profile) = try fixture()
        try put("{}", "settings.json", profile: profile)
        let importer = DevelopmentProfileImporter()
        XCTAssertThrowsError(try importer.prepare(profile: profile, sourcePreferences: { ["NXLibrary_SetupCompleted": true] }, savePreferences: { _ in throw CocoaError(.fileWriteNoPermission) }))
        var saved: [String: Any] = [:]
        XCTAssertTrue(try importer.prepare(profile: profile, sourcePreferences: { XCTFail("resume uses captured preferences"); return [:] }, savePreferences: { saved = $0 }))
        XCTAssertEqual(saved["NXLibrary_SetupCompleted"] as? Bool, true)
        XCTAssertEqual(try String(contentsOf: profile.stableSupportRoot.appendingPathComponent("settings.json")), "{}")
    }
    func testRefusesAnExistingUnownedDestination() throws {
        let (_, profile) = try fixture()
        try FileManager.default.createDirectory(at: profile.supportRoot, withIntermediateDirectories: true)
        XCTAssertThrowsError(try DevelopmentProfileImporter().prepare(profile: profile, sourcePreferences: { [:] }, savePreferences: { _ in XCTFail() }))
    }
    func testChangedSourceDoesNotActivatePartialCopy() throws {
        let (_, profile) = try fixture()
        try put("{}", "settings.json", profile: profile)
        var reads = 0
        XCTAssertThrowsError(try DevelopmentProfileImporter().prepare(profile: profile, sourcePreferences: {
            reads += 1
            return ["NXLibrary_SetupCompleted": reads == 1]
        }, savePreferences: { _ in XCTFail("must not activate") }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.supportRoot.path))
    }
    func testUnfinishedCopiedSessionEndsAtLastHeartbeatWithoutChangingTheOriginal() throws {
        let (_, profile) = try fixture()
        let session = PlaySession(gameID: UUID(), titleID: "fixture", bundleID: nil,
                                  startedAt: Date(timeIntervalSince1970: 100), lastHeartbeatAt: Date(timeIntervalSince1970: 160))
        let data = try JSONEncoder().encode([session])
        try FileManager.default.createDirectory(at: profile.stableSupportRoot, withIntermediateDirectories: true)
        let original = profile.stableSupportRoot.appendingPathComponent("play-sessions.json")
        try data.write(to: original)
        _ = try DevelopmentProfileImporter().prepare(profile: profile, sourcePreferences: { [:] }, savePreferences: { _ in })
        let copied = try JSONDecoder().decode([PlaySession].self, from: Data(contentsOf: profile.supportRoot.appendingPathComponent("play-sessions.json")))
        XCTAssertEqual(copied.first?.id, session.id)
        XCTAssertEqual(copied.first?.endedAt, session.lastHeartbeatAt)
        XCTAssertEqual(copied.first?.duration, 60)
        XCTAssertEqual(try Data(contentsOf: original), data)
    }
    func testRootsAreFoldersWhetherOrNotTheyExistYet() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for development in [false, true] {
            let profile = AppDataProfile(home: home, isDevelopment: development)
            for root in [profile.stableSupportRoot, profile.supportRoot, profile.cacheRoot] {
                XCTAssertTrue(root.hasDirectoryPath, root.path)
                XCTAssertEqual(root.appendingPathComponent("settings.json").deletingLastPathComponent(), root)
            }
        }
    }
    func testSharedAndScopedDefaultPathsAreConsistent() {
        XCTAssertEqual(AppSettingsStore.defaultURL().deletingLastPathComponent(), AppData.supportRoot)
        XCTAssertEqual(PlaySessionStore.defaultURL().deletingLastPathComponent(), AppData.supportRoot)
        XCTAssertEqual(MetadataPicks().directory, AppData.supportRoot)
        XCTAssertEqual(ArtworkStore.defaultDirectory(), AppData.supportRoot.appendingPathComponent("artwork"))
        XCTAssertEqual(SteamGridDBKey.defaultURL(), AppData.supportRoot.appendingPathComponent("steamgriddb-api-key"))
    }
    func testReleaseProfileNeverImports() throws {
        let (home, _) = try fixture()
        XCTAssertFalse(try DevelopmentProfileImporter().prepare(profile: AppDataProfile(home: home, isDevelopment: false), sourcePreferences: { XCTFail(); return [:] }, savePreferences: { _ in XCTFail() }))
    }
}
