import XCTest
import Combine
@testable import NXLibraryCore
@testable import ArcanePorting

@MainActor
final class CatalogSourcesModelTests: XCTestCase {
    private static let rescanSpacing: TimeInterval = 0.2

    func testDiscoveryUsesTheSavedSteamRootEvenWhenDisabled() throws {
        let (fixture, repository, _) = try prepared()
        let custom = fixture.root.appendingPathComponent("Custom Steam")
        let configuration = try repository.configureSource(.steam, enabled: false, root: custom).source(.steam)!
        let model = CatalogSourcesModel(repository: repository, initialConfiguration: configuration) { _ in }
        XCTAssertFalse(model.configuration.isEnabled)
        XCTAssertEqual(model.discoveryRoot, custom)
    }

    func testDiscoveryWithoutASavedRootUsesTheDefault() throws {
        let (_, repository, initial) = try prepared()
        let model = CatalogSourcesModel(repository: repository, initialConfiguration: initial) { _ in }
        XCTAssertEqual(model.discoveryRoot, CatalogSourcesModel.defaultSteamRoot)
    }

    private func prepared() throws -> (SteamTestFixture, CatalogRepository, CatalogSourceConfiguration) {
        let f = try SteamTestFixture.temporary(in: self)
        _ = try CatalogTestSupport.writeLegacy([CatalogTestSupport.completeLegacyGame()], to: f.root)
        let repository = CatalogRepository(store: CatalogStore(directory: f.root))
        return (f, repository, try repository.load().source(.steam)!)
    }
    private func snapshot(_ root: URL, id: UInt32 = 10, partial: Bool = false) -> SteamLibrarySnapshot {
        let content = root.appendingPathComponent("steamapps/common/Game")
        let app = content.appendingPathComponent("Game.app")
        let native = NativeMacApplication(url: app, executableURL: app.appendingPathComponent("Contents/MacOS/game"),
                                          bundleIdentifier: "test.steam", name: "Steam game", architectures: [.arm64],
                                          isDeclaredGame: true, fileObservations: [])
        return .init(libraries: [.init(root: root, isReadable: true, isComplete: !partial)],
                     games: [.init(appID: id, name: "Steam game", installationURL: content, libraryURL: root,
                                   reportedSizeBytes: 1, buildID: nil, nativeApps: [native], state: .nativeReady)],
                     issues: partial ? [.init(url: root, appID: nil, reason: .invalidManifest)] : [])
    }
    func testDisabledInitializationDoesNotScanAndEnableCommitsDiscovery() async throws {
        let (f, repository, initial) = try prepared()
        let done = expectation(description: "discovered")
        let calls = SourceCallCounter()
        let scan = snapshot(f.root)
        let model = CatalogSourcesModel(repository: repository, initialConfiguration: initial, scanner: { _, _ in calls.increment(); return scan }) { doc in
            if doc.games.contains(where: { $0.steamGame != nil }) { done.fulfill() }
        }
        XCTAssertEqual(calls.value, 0); XCTAssertEqual(model.status, .disabled)
        model.configure(enabled: true, root: f.root)
        await fulfillment(of: [done], timeout: 3)
        XCTAssertEqual(calls.value, 1); XCTAssertEqual(model.status, .ready)
        XCTAssertEqual(model.observedGameCount, 1)
        XCTAssertEqual(try repository.load().source(.steam)?.isEnabled, true)
    }
    func testDisableCancelsAndIgnoredWorkerCancellationStillCannotCommit() async throws {
        let (f, repository, initial) = try prepared()
        let entered = expectation(description: "worker")
        let gate = DispatchSemaphore(value: 0)
        let scan = snapshot(f.root)
        let rejected = expectation(description: "must not discover"); rejected.isInverted = true
        let model = CatalogSourcesModel(repository: repository, initialConfiguration: initial, scanner: { _, _ in
            entered.fulfill(); _ = gate.wait(timeout: .now() + 2); return scan
        }) { if $0.games.contains(where: { $0.steamGame != nil }) { rejected.fulfill() } }
        model.configure(enabled: true, root: f.root)
        await fulfillment(of: [entered], timeout: 3)
        model.configure(enabled: false, root: nil)
        gate.signal()
        await fulfillment(of: [rejected], timeout: 0.15)
        XCTAssertEqual(model.status, .disabled)
        XCTAssertEqual(try repository.load().games.count, 1)
    }
    func testCancelKeepsOptInAndExistingRecords() async throws {
        let (f, repository, initial) = try prepared()
        let entered = expectation(description: "worker")
        let gate = DispatchSemaphore(value: 0)
        let scan = snapshot(f.root)
        let model = CatalogSourcesModel(repository: repository, initialConfiguration: initial, scanner: { _, _ in
            entered.fulfill(); _ = gate.wait(timeout: .now() + 2); return scan
        }, onCommit: { _ in })
        model.configure(enabled: true, root: f.root)
        await fulfillment(of: [entered], timeout: 3)
        model.cancel(); gate.signal()
        XCTAssertEqual(model.status, .cancelled)
        XCTAssertEqual(try repository.load().source(.steam)?.isEnabled, true)
        XCTAssertEqual(try repository.load().games.count, 1)
    }
    func testNewRootWinsWhenOldWorkerReturnsLater() async throws {
        let (f, repository, initial) = try prepared()
        let entered = expectation(description: "old worker"), done = expectation(description: "new worker")
        let gate = DispatchSemaphore(value: 0), other = f.root.appendingPathComponent("Other")
        let oldCommitted = expectation(description: "old source must not commit"); oldCommitted.isInverted = true
        let old = snapshot(f.root, id: 10), new = snapshot(other, id: 20)
        let model = CatalogSourcesModel(repository: repository, initialConfiguration: initial, scanner: { root, _ in
            if root.path == f.root.path { entered.fulfill(); _ = gate.wait(timeout: .now() + 2); return old }
            return new
        }) {
            if $0.games.contains(where: { $0.steamGame?.appID == 20 }) { done.fulfill() }
            if $0.games.contains(where: { $0.steamGame?.appID == 10 }) { oldCommitted.fulfill() }
        }
        model.configure(enabled: true, root: f.root)
        await fulfillment(of: [entered], timeout: 3)
        model.configure(enabled: true, root: other)
        await fulfillment(of: [done], timeout: 3)
        gate.signal()
        await fulfillment(of: [oldCommitted], timeout: 0.15)
        XCTAssertEqual(try repository.load().games.compactMap { $0.steamGame?.appID }, [20])
        XCTAssertEqual(model.configuration.rootURL?.path, other.path)
        XCTAssertEqual(model.status, .ready)
    }
    func testFavoriteChangeWhileWorkerRunsIsRetained() async throws {
        let (f, repository, initial) = try prepared()
        let entered = expectation(description: "worker"), done = expectation(description: "committed")
        let gate = DispatchSemaphore(value: 0), scan = snapshot(f.root)
        let model = CatalogSourcesModel(repository: repository, initialConfiguration: initial, scanner: { _, _ in
            entered.fulfill(); _ = gate.wait(timeout: .now() + 2); return scan
        }) { if $0.games.contains(where: { $0.steamGame != nil }) { done.fulfill() } }
        model.configure(enabled: true, root: f.root)
        await fulfillment(of: [entered], timeout: 3)
        let id = try repository.load().games[0].id
        _ = try repository.setFavorite(false, for: id)
        gate.signal()
        await fulfillment(of: [done], timeout: 3)
        XCTAssertFalse(try repository.load().games[0].isFavorite)
        XCTAssertEqual(model.status, .ready)
    }
    func testFailedSourceCanRefreshIntoPartialSnapshotWithoutDroppingKnownData() async throws {
        let (f, repository, initial) = try prepared()
        let failed = expectation(description: "failure"), partial = expectation(description: "partial")
        let counter = SourceCallCounter(), scan = snapshot(f.root, partial: true)
        let model = CatalogSourcesModel(repository: repository, initialConfiguration: initial, scanner: { _, _ in
            if counter.increment() == 1 { throw POSIXError(.EACCES) }; return scan
        }, onCommit: { _ in })
        let observation = model.$status.sink { status in
            if status == .failed { failed.fulfill() }; if status == .partial { partial.fulfill() }
        }
        model.configure(enabled: true, root: f.root)
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertEqual(try repository.load().games.count, 1)
        model.refresh()
        await fulfillment(of: [partial], timeout: 3)
        XCTAssertEqual(try repository.load().games.count, 2)
        XCTAssertEqual(model.issues.count, 1)
        withExtendedLifetime(observation) {}
    }

    func testDownloadingGameIsNotCountedForReview() async throws {
        let (f, repository, initial) = try prepared()
        let done = expectation(description: "committed")
        let content = f.root.appendingPathComponent("steamapps/common/Game")
        let scan = SteamLibrarySnapshot(libraries: [.init(root: f.root, isReadable: true, isComplete: true)],
                                        games: [.init(appID: 10, name: "Steam game", installationURL: content, libraryURL: f.root,
                                                      reportedSizeBytes: 0, buildID: nil, nativeApps: [], state: .downloading)],
                                        issues: [])
        let model = CatalogSourcesModel(repository: repository, initialConfiguration: initial, scanner: { _, _ in scan }) { doc in
            if doc.games.contains(where: { $0.steamGame != nil }) { done.fulfill() }
        }
        model.configure(enabled: true, root: f.root)
        await fulfillment(of: [done], timeout: 3)
        XCTAssertEqual(model.observedGameCount, 1)
        XCTAssertEqual(model.reviewCount, 0)
    }

    // MARK: - Rescans when Steam rewrites a manifest

    func testEveryScanRechecksWatchedFoldersEvenWithTheSameLibraryPaths() async throws {
        let (f, repository, initial) = try prepared()
        let root = try f.library()
        let library = f.root.appendingPathComponent("Later")
        let scan = SteamLibrarySnapshot(libraries: [.init(root: root, isReadable: true, isComplete: true),
                                                  .init(root: library, isReadable: true, isComplete: true)],
                                       games: [], issues: [])
        let model = CatalogSourcesModel(repository: repository, initialConfiguration: initial,
                                        scanner: { _, _ in scan }, onCommit: { _ in })
        let watcher = SteamManifestWatcher()
        defer { watcher.stop() }
        let observation = model.$libraryRoots.sink { watcher.watch($0, root: root) }
        defer { withExtendedLifetime(observation) {} }
        model.configure(enabled: true, root: root)
        await settled(model)
        XCTAssertEqual(model.status, .ready)
        _ = try f.library("Later")
        model.refresh()
        await settled(model)
        XCTAssertEqual(model.status, .ready)
        let changed = expectation(description: "Watcher retries an unchanged path after the scan")
        watcher.onChange = { changed.fulfill() }
        try f.manifest(in: library)
        await fulfillment(of: [changed], timeout: 6)
    }

    private func settled(_ model: CatalogSourcesModel) async {
        for _ in 0..<200 where model.status == .scanning || model.status == .idle { try? await Task.sleep(nanoseconds: 10_000_000) }
    }
    private func watching(delay: TimeInterval = 0, extraLibraries: [URL] = []) async throws -> (CatalogSourcesModel, SourceCallCounter, URL) {
        let (f, repository, initial) = try prepared()
        let calls = SourceCallCounter()
        let base = snapshot(f.root)
        let scan: SteamLibrarySnapshot
        if !extraLibraries.isEmpty {
            scan = .init(libraries: ([f.root] + extraLibraries).map { .init(root: $0, isReadable: true, isComplete: true) },
                         games: base.games, issues: [])
        } else { scan = base }
        let model = CatalogSourcesModel(repository: repository, initialConfiguration: initial,
                                        scanner: { _, _ in calls.increment(); if delay > 0 { Thread.sleep(forTimeInterval: delay) }; return scan },
                                        rescanQuiet: 0.05, rescanSpacing: Self.rescanSpacing) { _ in }
        model.configure(enabled: true, root: f.root)
        await settled(model)
        return (model, calls, f.root)
    }

    func testLibraryRootsFollowTheCommittedScan() async throws {
        let external = URL(fileURLWithPath: "/tmp/catalog-external-library")
        let (model, _, root) = try await watching(extraLibraries: [external])
        XCTAssertEqual(model.libraryRoots, [root, external])
    }

    func testBurstOfChangesRescansOnce() async throws {
        let (model, calls, _) = try await watching()
        XCTAssertEqual(calls.value, 1)
        for _ in 0..<5 { model.steamFilesChanged(); try await Task.sleep(nanoseconds: 10_000_000) }
        try await Task.sleep(nanoseconds: 600_000_000)
        await settled(model)
        XCTAssertEqual(calls.value, 2)
    }

    func testChangeDuringScanRescansOnceAfterIt() async throws {
        let (model, calls, _) = try await watching(delay: 0.3)
        XCTAssertEqual(calls.value, 1)
        model.refresh()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(model.status, .scanning)
        for _ in 0..<3 { model.steamFilesChanged() }
        try await Task.sleep(nanoseconds: 1_200_000_000)
        await settled(model)
        XCTAssertEqual(calls.value, 3)
    }

    func testRescansAreSpacedApart() async throws {
        let (model, calls, _) = try await watching()
        let rescans = expectation(description: "both rescans start")
        rescans.expectedFulfillmentCount = 2
        var starts: [Date] = []
        let observation = model.$status.sink { status in
            guard status == .scanning else { return }
            starts.append(Date())
            if starts.count == 1 { model.steamFilesChanged() }
            rescans.fulfill()
        }
        defer { observation.cancel() }
        model.steamFilesChanged()
        await fulfillment(of: [rescans], timeout: 5)
        await settled(model)
        XCTAssertEqual(calls.value, 3)
        guard starts.count == 2 else { return XCTFail("Expected two rescan starts") }
        // Status publishes just after the model records the start time.
        XCTAssertGreaterThanOrEqual(starts[1].timeIntervalSince(starts[0]), Self.rescanSpacing - 0.01)
    }

    func testDisablingDropsAPendingRescanAndClearsLibraries() async throws {
        let (model, calls, root) = try await watching()
        XCTAssertEqual(model.libraryRoots, [root])
        model.steamFilesChanged()
        model.configure(enabled: false, root: root)
        XCTAssertEqual(model.libraryRoots, [])
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(calls.value, 1)
    }
}

private final class SourceCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    @discardableResult func increment() -> Int { lock.lock(); defer { lock.unlock() }; stored += 1; return stored }
    var value: Int { lock.lock(); defer { lock.unlock() }; return stored }
}
