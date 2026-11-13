import XCTest
@testable import NXLibraryCore

final class SteamLibrarySourceTests: XCTestCase {
    func testFindsTwoDistinctGamesAndDoesNotWriteSourceFiles() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        try f.manifest(in: root)
        try f.manifest(in: root, id: "20", name: "Second game", directory: "Second")
        try f.app(at: "Steam/steamapps/common/First/Game.app")
        try f.app(at: "Steam/steamapps/common/Second/Game.app")
        let before = try f.inventory()
        let result = try SteamLibrarySource(root: root).scan()
        XCTAssertEqual(result.games.map(\.appID), [10, 20])
        XCTAssertEqual(result.games.map(\.name), ["First game", "Second game"])
        XCTAssertEqual(result.games.map(\.state), [.nativeReady, .nativeReady])
        XCTAssertEqual(result.games.first?.reportedSizeBytes, 100)
        XCTAssertEqual(result.games.first?.buildID, "42")
        XCTAssertTrue(result.libraries.first?.isComplete == true)
        XCTAssertEqual(try f.inventory(), before)
    }

    func testModernAndLegacyIndexesIncludeExternalLibrariesAndDeduplicatePaths() throws {
        for modern in [false, true] {
            let f = try SteamTestFixture.temporary(in: self)
            let root = try f.library(), external = try f.library("External library")
            try f.manifest(in: external)
            try f.app(at: "External library/steamapps/common/First/Game.app")
            let value = modern ? "{ path \(SteamTestFixture.quote(external.path)) label \"\" }" : SteamTestFixture.quote(external.path)
            let index = "libraryfolders { 0 { path \(SteamTestFixture.quote(root.path)) } 1 \(value) 2 \(value) }"
            try Data(index.utf8).write(to: root.appendingPathComponent("steamapps/libraryfolders.vdf"))
            let result = try SteamLibrarySource(root: root).scan()
            XCTAssertEqual(result.libraries.count, 2)
            XCTAssertEqual(result.games.map(\.appID), [10])
        }
    }

    func testMissingOrMalformedIndexDoesNotHideDefaultLibraryOrItsError() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        try f.manifest(in: root)
        try f.app(at: "Steam/steamapps/common/First/Game.app")
        XCTAssertEqual(try SteamLibrarySource(root: root).scan().games.count, 1)
        try Data("libraryfolders {".utf8).write(to: root.appendingPathComponent("steamapps/libraryfolders.vdf"))
        let partial = try SteamLibrarySource(root: root).scan()
        XCTAssertEqual(partial.games.count, 1)
        XCTAssertTrue(partial.issues.contains { $0.reason == .invalidIndex })
        XCTAssertFalse(partial.libraries[0].isComplete)
    }

    func testUnavailableExternalLibraryIsNotASuccessfulEmptyScan() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library(), absent = f.root.appendingPathComponent("disconnected")
        let index = "libraryfolders { 1 { path \(SteamTestFixture.quote(absent.path)) } }"
        try Data(index.utf8).write(to: root.appendingPathComponent("steamapps/libraryfolders.vdf"))
        let result = try SteamLibrarySource(root: root).scan()
        let observation = try XCTUnwrap(result.libraries.first { $0.root.path == absent.path })
        XCTAssertFalse(observation.isReadable)
        XCTAssertFalse(observation.isComplete)
        XCTAssertTrue(result.issues.contains { $0.reason == .unavailableLibrary })
    }

    func testInvalidManifestRetainsFilenameIdentityInIssueContext() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        let manifest = try f.manifest(in: root)
        try Data("AppState {".utf8).write(to: manifest)
        let result = try SteamLibrarySource(root: root).scan()
        XCTAssertTrue(result.games.isEmpty)
        XCTAssertTrue(result.issues.contains { $0.reason == .invalidManifest && $0.appID == 10 })
        XCTAssertFalse(result.libraries[0].isComplete)
    }

    func testRejectsMismatchedOrInvalidAppIdentifiers() throws {
        for id in ["20", "+10", "0", "4294967296", "a10"] {
            let f = try SteamTestFixture.temporary(in: self)
            let root = try f.library()
            try f.manifest(in: root, id: id, filenameID: "10")
            let result = try SteamLibrarySource(root: root).scan()
            XCTAssertTrue(result.games.isEmpty, id)
            XCTAssertFalse(result.issues.isEmpty, id)
        }
    }

    func testEscapedUnicodeNamesAndInvalidOptionalSizes() throws {
        for size in ["-1", "9223372036854775808"] {
            let f = try SteamTestFixture.temporary(in: self)
            let root = try f.library()
            try f.manifest(in: root, name: "L'avventura \"è\" bella", directory: "Gioco è", size: size)
            try f.app(at: "Steam/steamapps/common/Gioco è/Game.app")
            let result = try SteamLibrarySource(root: root).scan()
            XCTAssertEqual(result.games.first?.name, "L'avventura \"è\" bella")
            XCTAssertNil(result.games.first?.reportedSizeBytes)
            XCTAssertEqual(result.games.first?.state, .nativeReady)
        }
    }

    func testUnsafeInstallDirectoryDoesNotEscapeTheLibrary() throws {
        for directory in ["../escape", "/tmp/escape", "First/../../escape"] {
            let f = try SteamTestFixture.temporary(in: self)
            let root = try f.library()
            try f.manifest(in: root, directory: directory)
            let result = try SteamLibrarySource(root: root).scan()
            XCTAssertTrue(result.games.isEmpty)
            XCTAssertTrue(result.issues.contains { $0.reason == .unsafePath })
        }
    }

    func testSymlinkInstallEscapeIsRejected() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        try f.manifest(in: root)
        let externalApp = try f.app(at: "Elsewhere/Game.app")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("steamapps/common/First"),
                                                  withDestinationURL: externalApp.deletingLastPathComponent())
        let result = try SteamLibrarySource(root: root).scan()
        XCTAssertTrue(result.games.isEmpty)
        XCTAssertTrue(result.issues.contains { $0.reason == .unsafePath })
    }

    func testSymlinkedSteamappsCannotSupplyAnIndexOutsideTheChosenRoot() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library(), foreign = try f.library("Foreign"), third = try f.library("Third")
        try f.manifest(in: third)
        try f.app(at: "Third/steamapps/common/First/Game.app")
        try Data("libraryfolders { 1 \(SteamTestFixture.quote(third.path)) }".utf8)
            .write(to: foreign.appendingPathComponent("steamapps/libraryfolders.vdf"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("steamapps"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("steamapps"),
                                                  withDestinationURL: foreign.appendingPathComponent("steamapps"))
        let result = try SteamLibrarySource(root: root).scan()
        XCTAssertTrue(result.games.isEmpty)
        XCTAssertEqual(result.libraries.count, 1)
        XCTAssertTrue(result.issues.contains { $0.reason == .unsafePath })
    }

    func testLibraryAndManifestLimitsAreReported() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library(), external = try f.library("External")
        try f.manifest(in: root)
        try f.manifest(in: root, id: "20", directory: "Second")
        try Data("libraryfolders { 1 \(SteamTestFixture.quote(external.path)) }".utf8)
            .write(to: root.appendingPathComponent("steamapps/libraryfolders.vdf"))
        var limits = SteamScanLimits.standard
        limits.maximumLibraries = 1
        limits.maximumManifests = 1
        let result = try SteamLibrarySource(root: root, limits: limits).scan()
        XCTAssertEqual(result.libraries.count, 1)
        XCTAssertEqual(result.games.count, 1)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.issues.contains { $0.reason == .libraryLimit })
        XCTAssertTrue(result.issues.contains { $0.reason == .manifestLimit })
    }

    func testDuplicateAppIdsAcrossLibrariesRemainAmbiguousObservations() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library(), second = try f.library("Other")
        for library in [root, second] { try f.manifest(in: library) }
        try f.app(at: "Steam/steamapps/common/First/Game.app")
        try f.app(at: "Other/steamapps/common/First/Game.app")
        try Data("libraryfolders { 1 \(SteamTestFixture.quote(second.path)) }".utf8)
            .write(to: root.appendingPathComponent("steamapps/libraryfolders.vdf"))
        let result = try SteamLibrarySource(root: root).scan()
        XCTAssertEqual(result.games.count, 2)
        XCTAssertTrue(result.games.allSatisfy { $0.state == .requiresReview })
        XCTAssertTrue(result.issues.contains { $0.reason == .conflictingIdentity })
    }

    func testMainGameAndHelperAreNotTwoGames() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        try f.manifest(in: root)
        try f.app(at: "Steam/steamapps/common/First/Game.app")
        try f.app(at: "Steam/steamapps/common/First/Helper.app", category: nil)
        let result = try SteamLibrarySource(root: root).scan()
        XCTAssertEqual(result.games.first?.state, .nativeReady)
        XCTAssertEqual(result.games.first?.nativeApps.filter(\.isDeclaredGame).count, 1)
    }

    func testRecognizedTopLevelGameDoesNotRequireWalkingItsLooseDataTree() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        try f.manifest(in: root)
        try f.app(at: "Steam/steamapps/common/First/Game.app")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("steamapps/common/First/LooseData/deep/assets"),
                                                withIntermediateDirectories: true)
        var limits = SteamScanLimits.standard
        limits.maximumDirectoriesPerInstall = 1
        let result = try SteamLibrarySource(root: root, limits: limits).scan()
        XCTAssertEqual(result.games.first?.state, .nativeReady)
        XCTAssertTrue(result.isComplete)
    }

    func testToolsUnclassifiedAndMultipleMainAppsAreNotConfirmedGames() throws {
        for categories: [String?] in [["public.app-category.developer-tools"], [nil],
                                    ["public.app-category.games", "public.app-category.games"]] {
            let f = try SteamTestFixture.temporary(in: self)
            let root = try f.library()
            try f.manifest(in: root)
            for (i, category) in categories.enumerated() {
                try f.app(at: "Steam/steamapps/common/First/App\(i).app", category: category)
            }
            XCTAssertEqual(try SteamLibrarySource(root: root).scan().games.first?.state, .requiresReview)
        }
    }

    func testMissingContentAndWindowsOnlyDirectoryAreNotNativeReady() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        try f.manifest(in: root)
        XCTAssertEqual(try SteamLibrarySource(root: root).scan().games.first?.state, .unavailable)
        let install = root.appendingPathComponent("steamapps/common/First")
        try FileManager.default.createDirectory(at: install, withIntermediateDirectories: true)
        try Data("synthetic".utf8).write(to: install.appendingPathComponent("game.exe"))
        XCTAssertEqual(try SteamLibrarySource(root: root).scan().games.first?.state, .unavailable)
    }

    func testLimitsDoNotReturnADeceptivelyCompleteLibrary() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        try f.manifest(in: root)
        try f.app(at: "Steam/steamapps/common/First/deep/Game.app")
        var limits = SteamScanLimits.standard
        limits.maximumDirectoriesPerInstall = 1
        let limited = try SteamLibrarySource(root: root, limits: limits).scan()
        XCTAssertFalse(limited.libraries[0].isComplete)
        XCTAssertTrue(limited.issues.contains { $0.reason == .directoryLimit })
        limits = .standard
        limits.maximumTextBytes = 10
        let oversized = try SteamLibrarySource(root: root, limits: limits).scan()
        XCTAssertTrue(oversized.games.isEmpty)
        XCTAssertTrue(oversized.issues.contains { $0.reason == .oversizedManifest })
    }

    func testCancellationThrowsRatherThanPublishingPartialResults() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        XCTAssertThrowsError(try SteamLibrarySource(root: root).scan(cancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
    }

    func testSourceSnapshotDetectsAFileChangingBeforePublication() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        let file = try f.manifest(in: root)
        let snapshot = try InstallationFileSnapshot.read(at: file, maximumBytes: 1024)
        try Data("changed".utf8).write(to: file, options: .atomic)
        XCTAssertThrowsError(try snapshot.verifyUnchanged())
        XCTAssertEqual(try String(contentsOf: file), "changed")
    }
}
