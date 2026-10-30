import XCTest
@testable import NXLibraryCore

final class PortingPresentationTests: XCTestCase {
    private func progress(_ events: [BuildEvent]) -> PortingProgress {
        var progress = PortingProgress()
        events.forEach { progress.apply($0) }
        return progress
    }

    private var inShaders: PortingProgress {
        progress([.stage(k: 5, n: 7, name: "Mac shaders", step: nil),
                  .progress(fraction: 0.5, done: nil, total: nil, unit: nil, eta: 420)])
    }

    private var finishing: PortingProgress {
        progress([.stage(k: 5, n: 7, name: "Mac shaders", step: nil),
                  .stageEnd(name: "Mac shaders", ok: true, elapsed: 600, summary: nil),
                  .stage(k: 6, n: 7, name: "Mac host", step: nil),
                  .stageEnd(name: "Mac host", ok: true, elapsed: 30, summary: nil),
                  .stage(k: 7, n: 8, name: "Pipeline archive", step: nil)])
    }

    private func game(app: Bool, failure: PortingFailure? = nil) -> PortedGame {
        var game = PortedGame(name: "LumenTale",
                              url: URL(fileURLWithPath: app ? "/Applications/LumenTale.app" : "/Games/LumenTale"),
                              platform: .macApp, sizeBytes: 0, modificationDate: Date(timeIntervalSince1970: 0))
        game.status = app ? .built : .notBuilt
        game.portingFailure = failure
        return game
    }

    // MARK: - ETA

    func testETAAddsTheLastFinishingTimeToTheShaders() {
        XCTAssertEqual(PortingETA.text(inShaders, lastFinishingSeconds: 150), "About 10 min left")
    }

    func testETAWithoutAPreviousPortingShowsTheShadersOnly() {
        XCTAssertEqual(PortingETA.text(inShaders, lastFinishingSeconds: nil), "Shaders: about 7 min")
    }

    func testETANeverShowsLessThanAMinute() {
        let almost = progress([.stage(k: 5, n: 7, name: "Mac shaders", step: nil),
                               .progress(fraction: 0.99, done: nil, total: nil, unit: nil, eta: 20)])
        XCTAssertEqual(PortingETA.text(almost, lastFinishingSeconds: nil), "Shaders: about 1 min")
    }

    func testNoETABeforeTheShaders() {
        let preparing = progress([.stage(k: 3, n: 7, name: "rewrite", step: nil)])
        XCTAssertNil(PortingETA.text(preparing, lastFinishingSeconds: 150))
    }

    func testETAWhileFinishingCountsDownTheLastTime() {
        XCTAssertEqual(PortingETA.text(finishing, lastFinishingSeconds: 150), "About 2 min left")
        XCTAssertEqual(PortingETA.text(finishing, lastFinishingSeconds: nil), "Finishing up")
    }

    // MARK: - Tile look

    func testTileFollowsThePortingPhase() {
        let porting = game(app: false)
        let preparing = progress([.stage(k: 3, n: 7, name: "rewrite", step: nil)])
        XCTAssertEqual(PortingTileLook.make(game: porting, portingGameID: porting.id, progress: preparing),
                       .preparing(step: 3, count: 7))
        XCTAssertEqual(PortingTileLook.make(game: porting, portingGameID: porting.id, progress: inShaders),
                       .filling(0.45))
        XCTAssertEqual(PortingTileLook.make(game: porting, portingGameID: UUID(), progress: inShaders), .normal)
    }

    func testLockOnlyWithoutAWorkingApp() {
        let failed = game(app: false, failure: .failed)
        XCTAssertEqual(PortingTileLook.make(game: failed, portingGameID: nil, progress: nil), .locked)
        let rebuild = game(app: true, failure: .failed)
        XCTAssertEqual(PortingTileLook.make(game: rebuild, portingGameID: nil, progress: nil), .normal)
        XCTAssertEqual(PortingTileLook.make(game: game(app: false, failure: .cancelled), portingGameID: nil,
                                            progress: nil), .locked)
    }

    // MARK: - Pills

    func testPillsFollowThePorting() {
        let fresh = game(app: false)
        XCTAssertEqual(PortingPills.make(game: fresh, portingGameID: fresh.id), .porting)
        XCTAssertEqual(PortingPills.porting.count, 1)
        XCTAssertEqual(PortingPills.make(game: fresh, portingGameID: nil), .normal)
        XCTAssertEqual(PortingPills.make(game: game(app: false, failure: .failed), portingGameID: nil),
                       .failed(.failed))
        XCTAssertEqual(PortingPills.failed(.failed).count, 3)
        XCTAssertEqual(PortingPills.make(game: game(app: true, failure: .cancelled), portingGameID: nil),
                       .normalAfterFailure(.cancelled))
        XCTAssertEqual(PortingPills.normalAfterFailure(.failed).count, 3)
    }

    // MARK: - The failure survives a relaunch

    func testFailureIsSavedWithTheGame() throws {
        let saved = try JSONEncoder().encode(game(app: false, failure: .failed))
        XCTAssertEqual(try JSONDecoder().decode(PortedGame.self, from: saved).portingFailure, .failed)
        var old = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
        old.removeValue(forKey: "portingFailure")
        let legacy = try JSONSerialization.data(withJSONObject: old)
        XCTAssertNil(try JSONDecoder().decode(PortedGame.self, from: legacy).portingFailure)
    }

    // MARK: - Spotlight

    func testThePortingGameIsTheFirstTile() {
        let a = UUID(), b = UUID()
        let games = [game(app: true), game(app: false)].enumerated().map { index, game -> PortedGame in
            var game = game
            game.id = index == 0 ? a : b
            return game
        }
        let row = SpotlightRow.build(games: games, enabledCards: [.collection, .addGame], order: [], front: b)
        XCTAssertEqual(row.first, .game(b))
        XCTAssertEqual(row.count, 4)
        XCTAssertEqual(SpotlightRow.build(games: games, enabledCards: [.collection], order: [], front: UUID()),
                       SpotlightRow.build(games: games, enabledCards: [.collection], order: []))
    }

    func testPillMovesStopAtTheLimit() {
        var state = SpotlightState(focus: .pills, pillIndex: 2)
        state.setPillLimit(1)
        XCTAssertEqual(state.pillIndex, 0)
        XCTAssertFalse(state.moveSideways(by: 1, screenshotCount: 0))
        var details = DetailsFocus()
        details.pill = 2
        details.setPillLimit(1)
        XCTAssertEqual(details.pill, 0)
        XCTAssertFalse(details.right(in: DetailsFocus.Bands(screenshots: 0, actions: 0, more: 0)))
    }

    func testLockIcon() {
        XCTAssertEqual(MaterialIcon.lock.rawValue, "\u{E897}")
    }
}
