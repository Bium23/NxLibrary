import XCTest
@testable import NXLibraryCore

final class GameResourceStateTests: XCTestCase {
    private func game(_ status: GameStatus, app: Bool = true) -> PortedGame {
        var result = PortedGame(name: "Synthetic", url: URL(fileURLWithPath: app ? "/Applications/Synthetic.app" : "/workspace/Synthetic"),
                                platform: .macApp, sizeBytes: 0, modificationDate: .distantPast)
        result.status = status
        return result
    }

    func testMissingInstalledAppIsUnavailableAndRestoresWhenPresentAgain() {
        var existing = game(.built)
        existing.status = GameResourceState.reconciledStatus(for: existing, appExists: false, sourcesAvailable: false)
        XCTAssertEqual(existing.status, .appMissing)
        let presentation = GameDetailPresentation(game: existing, metadata: nil, totalPlaytime: 0, lastPlayed: nil)
        XCTAssertFalse(presentation.canPlay)
        XCTAssertTrue(presentation.sourcesDetached)
        XCTAssertEqual(GameResourceState.unavailableReason(for: existing), .appMissing)
        XCTAssertEqual(PortingPills.make(game: existing, portingGameID: nil), .unavailable(.appMissing))
        existing.status = GameResourceState.reconciledStatus(for: existing, appExists: true, sourcesAvailable: false)
        XCTAssertEqual(existing.status, .builtSourcesMissing)
        XCTAssertTrue(existing.isPlayableLocally)
        XCTAssertNil(GameResourceState.unavailableReason(for: existing))
    }

    func testUnbuiltWorkspaceDoesNotBecomeMissingApp() {
        let unbuilt = game(.notBuilt, app: false)
        XCTAssertEqual(GameResourceState.reconciledStatus(for: unbuilt, appExists: false, sourcesAvailable: false), .notBuilt)
        var old = game(.appMissing, app: false)
        XCTAssertEqual(GameResourceState.reconciledStatus(for: old, appExists: false, sourcesAvailable: false), .notBuilt)
        old.portingFailure = .failed
        XCTAssertEqual(GameResourceState.reconciledStatus(for: old, appExists: false, sourcesAvailable: true), .failed)
    }

    func testRefreshPreservesActiveBuild() {
        let building = game(.building)
        XCTAssertEqual(GameResourceState.reconciledStatus(for: building, appExists: false, sourcesAvailable: false), .building)
    }

    func testPhysicalSourcesControlRebuildWithoutBlockingExistingApp() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("NX-Source-\(UUID()).nsp")
        defer { try? FileManager.default.removeItem(at: source) }
        var pending = game(.notBuilt, app: false)
        pending.sources = [GameFileItem(url: source, kind: .base, sizeBytes: 1)]
        XCTAssertEqual(GameResourceState.unavailableReason(for: pending), .sourcesMissing)
        XCTAssertEqual(PortingPills.make(game: pending, portingGameID: nil), .unavailable(.sourcesMissing))
        try Data("synthetic".utf8).write(to: source)
        XCTAssertTrue(GameResourceState.sourcesAvailable(for: pending))
        XCTAssertNil(GameResourceState.unavailableReason(for: pending))
        XCTAssertEqual(PortingPills.make(game: pending, portingGameID: nil), .normal)
        try FileManager.default.removeItem(at: source)
        pending.url = URL(fileURLWithPath: "/Applications/Synthetic.app")
        pending.status = .builtSourcesMissing
        XCTAssertTrue(pending.isPlayableLocally)
        XCTAssertNil(GameResourceState.unavailableReason(for: pending))
    }

    func testRemovedAppMessageTakesPriorityOverPreviousRebuildFailure() {
        var missing = game(.appMissing)
        missing.portingFailure = .failed
        XCTAssertEqual(PortingPills.make(game: missing, portingGameID: nil), .unavailable(.appMissing))
    }
}
