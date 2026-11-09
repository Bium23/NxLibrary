import XCTest
@testable import NXLibraryCore

final class PortingPresentationTests: XCTestCase {
    private func progress(_ events: [BuildEvent]) -> PortingProgress {
        var progress = PortingProgress()
        events.forEach { progress.apply($0) }
        return progress
    }

    private var inShaders: PortingProgress {
        progress([.stage(k: 5, n: 7, name: "Mac shaders", step: nil), .step("compiling"),
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
        let almost = progress([.stage(k: 5, n: 7, name: "Mac shaders", step: nil), .step("compiling"),
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

        // Live ETA during Pipeline archive takes precedence
        var pipelineArchive = finishing
        pipelineArchive.apply(.progress(fraction: 0.5, done: 1000, total: 2000, unit: "pipelines", eta: 5400))
        XCTAssertEqual(PortingETA.text(pipelineArchive, lastFinishingSeconds: 150), "About 1 hr 30 min left")
        XCTAssertEqual(PortingETA.text(pipelineArchive, lastFinishingSeconds: nil), "About 1 hr 30 min left")
    }

    func testETAFormatsHoursAndMinutesWhenOverAnHour() {
        let oneHour = progress([.stage(k: 5, n: 7, name: "Mac shaders", step: nil), .step("compiling"),
                                .progress(fraction: 0.1, done: nil, total: nil, unit: nil, eta: 3600)])
        XCTAssertEqual(PortingETA.text(oneHour, lastFinishingSeconds: nil), "Shaders: about 1 hr")

        let longShaders = progress([.stage(k: 5, n: 7, name: "Mac shaders", step: nil), .step("compiling"),
                                    .progress(fraction: 0.5, done: nil, total: nil, unit: nil, eta: 15165)])
        XCTAssertEqual(PortingETA.text(longShaders, lastFinishingSeconds: nil), "Shaders: about 4 hr 13 min")
        XCTAssertEqual(PortingETA.text(longShaders, lastFinishingSeconds: 120), "About 4 hr 15 min left")

        let longFinishing = progress([.stage(k: 5, n: 7, name: "Mac shaders", step: nil),
                                      .stageEnd(name: "Mac shaders", ok: true, elapsed: 600, summary: nil),
                                      .stage(k: 6, n: 7, name: "Mac host", step: nil)])
        XCTAssertEqual(PortingETA.text(longFinishing, lastFinishingSeconds: 3600), "About 1 hr left")
        XCTAssertEqual(PortingETA.text(longFinishing, lastFinishingSeconds: 3900), "About 1 hr 5 min left")
    }

    // MARK: - Stage Elapsed Time

    func testElapsedFormatsSecondsMinutesAndHours() {
        XCTAssertEqual(PortingETA.elapsed(0), "0 s")
        XCTAssertEqual(PortingETA.elapsed(6), "6 s")
        XCTAssertEqual(PortingETA.elapsed(59.4), "59 s")
        XCTAssertEqual(PortingETA.elapsed(60), "1:00")
        XCTAssertEqual(PortingETA.elapsed(61), "1:01")
        XCTAssertEqual(PortingETA.elapsed(397), "6:37")
        XCTAssertEqual(PortingETA.elapsed(3599), "59:59")
        XCTAssertEqual(PortingETA.elapsed(3600), "1:00:00")
        XCTAssertEqual(PortingETA.elapsed(3665), "1:01:05")
        // 252 minutes 45 seconds (15165 s) -> 4 hours 12 minutes 45 seconds
        XCTAssertEqual(PortingETA.elapsed(15165), "4:12:45")
    }

    // MARK: - Tile look

    func testTileFollowsThePortingPhase() {
        let porting = game(app: false)
        let preparing = progress([.stage(k: 3, n: 7, name: "rewrite", step: "checking the inputs")])
        XCTAssertEqual(PortingTileLook.make(game: porting, portingGameID: porting.id, progress: preparing),
                       .preparing(step: 3, count: 7, title: "Rewrite", detail: "checking the inputs"))
        XCTAssertEqual(PortingTileLook.make(game: porting, portingGameID: porting.id, progress: inShaders),
                       .filling(0.45))
        XCTAssertEqual(PortingTileLook.make(game: porting, portingGameID: UUID(), progress: inShaders), .locked)
    }

    func testLockOnlyWithoutAWorkingApp() {
        let failed = game(app: false, failure: .failed)
        XCTAssertEqual(PortingTileLook.make(game: failed, portingGameID: nil, progress: nil), .locked)
        let rebuild = game(app: true, failure: .failed)
        XCTAssertEqual(PortingTileLook.make(game: rebuild, portingGameID: nil, progress: nil), .normal)
        XCTAssertEqual(PortingTileLook.make(game: game(app: false, failure: .cancelled), portingGameID: nil,
                                            progress: nil), .locked)
    }

    func testMissingAppUsesLockAndUnavailableActions() {
        var missing = game(app: true)
        missing.status = .appMissing
        XCTAssertEqual(PortingTileLook.make(game: missing, portingGameID: nil, progress: nil), .locked)
        XCTAssertNotEqual(PortingPills.make(game: missing, portingGameID: nil), .normal)
    }

    func testMissingSourceFilesDoNotOfferPlayOrAttachSourcesAsPrimaryAction() {
        var missing = game(app: false)
        missing.sources = [GameFileItem(url: URL(fileURLWithPath: "/missing-\(UUID())/base.nsp"), kind: .base, sizeBytes: 1)]
        XCTAssertNotEqual(PortingPills.make(game: missing, portingGameID: nil), .normal)
    }

    func testWorkingAppStaysPlayableWhenSourcesAreUnavailable() {
        var existing = game(app: true)
        existing.status = .builtSourcesMissing
        existing.sources = [GameFileItem(url: URL(fileURLWithPath: "/missing-\(UUID())/base.nsp"), kind: .base, sizeBytes: 1)]
        XCTAssertEqual(PortingTileLook.make(game: existing, portingGameID: nil, progress: nil), .normal)
        XCTAssertEqual(PortingPills.make(game: existing, portingGameID: nil), .normal)
        XCTAssertTrue(existing.isPlayableLocally)
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

    /// The porting game is the first game: right after the Add game card, never before the cards.
    func testThePortingGameSitsRightAfterAddGame() {
        let a = UUID(), b = UUID()
        let games = [game(app: true), game(app: false)].enumerated().map { index, game -> PortedGame in
            var game = game
            game.id = index == 0 ? a : b
            return game
        }
        let row = SpotlightRow.build(games: games, enabledCards: [.collection, .addGame], order: [], front: b)
        XCTAssertEqual(row, [.card(.collection), .card(.addGame), .game(b), .game(a)])
        // The player moved Add game to the end: the porting game still follows it.
        let moved = SpotlightRow.build(games: games, enabledCards: [.collection, .addGame],
                                       order: ["card:collection", "game:\(a.uuidString)", "game:\(b.uuidString)", "card:addGame"],
                                       front: b)
        XCTAssertEqual(moved, [.card(.collection), .game(a), .card(.addGame), .game(b)])
        // Without the card: first among the games.
        let noCard = SpotlightRow.build(games: games, enabledCards: [.collection], order: [], front: b)
        XCTAssertEqual(noCard, [.card(.collection), .game(b), .game(a)])
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
