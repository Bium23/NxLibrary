import XCTest
import Combine
@testable import NXLibraryCore

@MainActor
final class CatalogSourcesModelTests: XCTestCase {
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
}

private final class SourceCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    @discardableResult func increment() -> Int { lock.lock(); defer { lock.unlock() }; stored += 1; return stored }
    var value: Int { lock.lock(); defer { lock.unlock() }; return stored }
}
