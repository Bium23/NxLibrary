import CoreGraphics
import XCTest
@testable import NXLibraryCore

final class SpotlightEntranceTests: XCTestCase {
    private let row: CGFloat = 1760

    /// Tiles of side 174 with a gap of 26, the first one starting at `start`.
    private func tiles(_ count: Int, from start: CGFloat = 80) -> [ClosedRange<CGFloat>] {
        (0..<count).map { index in
            let lower = start + CGFloat(index) * 200
            return lower...(lower + 174)
        }
    }

    func testFirstTileFliesInFromTheCentreWhileItGrows() throws {
        let flight = try XCTUnwrap(SpotlightEntrance.flights(tiles: [80...254], rowWidth: row).first ?? nil)
        XCTAssertEqual(flight.delay, 0.6, accuracy: 0.0001)
        XCTAssertEqual(flight.fromScale, 0.35, accuracy: 0.0001)
        XCTAssertEqual(flight.fromY, -18, accuracy: 0.0001)
        XCTAssertEqual(flight.duration, 0.9, accuracy: 0.0001)
        XCTAssertEqual(flight.fadeDuration, 0.5, accuracy: 0.0001)
        XCTAssertEqual(flight.fromX, (880 - 167) * 0.75, accuracy: 0.0001)
        XCTAssertFalse(flight.fadesOnly)
    }

    func testDelayGrowsBySixtyMillisecondsPerFlownTile() throws {
        let flights = SpotlightEntrance.flights(tiles: tiles(3), rowWidth: row)
        let third = try XCTUnwrap(flights[2])
        XCTAssertEqual(third.delay, 0.72, accuracy: 0.0001)
    }

    func testTilesLeftOfTheStageDoNotFly() throws {
        let flights = SpotlightEntrance.flights(tiles: [(-300)...(-126), 80...254], rowWidth: row)
        XCTAssertNil(flights[0])
        let first = try XCTUnwrap(flights[1])
        XCTAssertEqual(first.delay, 0.6, accuracy: 0.0001, "a tile off the left edge does not count")
    }

    func testTilesPastTheRightEdgeOnlyFade() throws {
        // Two on the stage, then fourteen past its right edge.
        let flights = SpotlightEntrance.flights(tiles: tiles(2, from: 1400) + tiles(14, from: 1800), rowWidth: row)
        let firstLate = try XCTUnwrap(flights[2])
        XCTAssertTrue(firstLate.fadesOnly)
        XCTAssertEqual(firstLate.delay, 0.6 + 2 * 0.06, accuracy: 0.0001)
        XCTAssertEqual(firstLate.fromScale, 1)
        XCTAssertEqual(firstLate.fromX, 0)
        XCTAssertEqual(firstLate.fromY, 0)
        let secondLate = try XCTUnwrap(flights[3])
        XCTAssertEqual(secondLate.delay, firstLate.delay, accuracy: 0.0001, "fading tiles do not move the schedule")
        XCTAssertNotNil(flights[13], "the twelfth tile past the edge still fades")
        XCTAssertNil(flights[14], "the thirteenth and later stay as they are")
        XCTAssertNil(flights[15])
    }

    func testDurationEndsWithTheLastLanding() {
        let flights = SpotlightEntrance.flights(tiles: tiles(10, from: 0), rowWidth: 2000)
        XCTAssertEqual(SpotlightEntrance.duration(of: flights), 0.6 + 9 * 0.06 + 0.9, accuracy: 0.0001)
        XCTAssertEqual(SpotlightEntrance.duration(of: []), 0)
    }

    func testPlaysOnlyOnFirstSpotlightWithTheSwitchOnAndWithoutReduceMotion() {
        XCTAssertTrue(SpotlightEntrance.plays(isFirstHome: true, route: .library, reduceMotion: false, enabled: true))
        XCTAssertFalse(SpotlightEntrance.plays(isFirstHome: true, route: .collection, reduceMotion: false, enabled: true))
        XCTAssertFalse(SpotlightEntrance.plays(isFirstHome: true, route: .library, reduceMotion: true, enabled: true))
        XCTAssertFalse(SpotlightEntrance.plays(isFirstHome: false, route: .library, reduceMotion: false, enabled: true))
        XCTAssertFalse(SpotlightEntrance.plays(isFirstHome: true, route: .library, reduceMotion: false, enabled: false),
                       "Settings → Start-up → Entrance off: the library shows at once")
    }

    func testNoInputUntilTheEntranceHasLanded() {
        for phase: SpotlightEntrance.Phase in [.covered, .waiting, .playing] {
            XCTAssertFalse(phase.takesInput, "no key, click, wheel or press skips the entrance (\(phase))")
        }
        XCTAssertTrue(SpotlightEntrance.Phase.landed.takesInput)
    }

    func testTopBarAndHintsComeInLast() {
        XCTAssertEqual(SpotlightEntrance.controlsFade, 0.4, "top bar and button hints fade in together once everything has landed")
    }

    func testAStartedFlightAlwaysLandsWellAfterTheLongest() {
        let flights = SpotlightEntrance.flights(tiles: (0..<30).map { CGFloat($0 * 190)...CGFloat($0 * 190 + 174) },
                                                rowWidth: 1920)
        XCTAssertGreaterThan(SpotlightEntrance.longestWait, SpotlightEntrance.end(of: flights) + 1)
        XCTAssertLessThanOrEqual(SpotlightEntrance.longestWait, 5)
    }

    func testLandingPutsAWaitingOrPlayingEntranceInPlace() {
        var waiting = SpotlightEntrance.Phase.waiting
        waiting.land()
        XCTAssertEqual(waiting, .landed)

        var playing = SpotlightEntrance.Phase.playing
        playing.land()
        XCTAssertEqual(playing, .landed)

        var landed = SpotlightEntrance.Phase.landed
        landed.uncover()
        landed.start()
        XCTAssertEqual(landed, .landed, "a landed entrance never plays again")
    }

    func testCoveredWaitsUntilUncovered() {
        var phase = SpotlightEntrance.Phase.covered
        phase.start()
        XCTAssertEqual(phase, .covered, "nothing flies under the intro or the welcome")
        phase.uncover()
        XCTAssertEqual(phase, .waiting)
        phase.start()
        XCTAssertEqual(phase, .playing)
    }

    func testABreathOnTheMoonlightThenASlowBackground() {
        XCTAssertEqual(SpotlightEntrance.hold, 0.5)
        XCTAssertEqual(SpotlightEntrance.backgroundDuration, 1.4)
        XCTAssertEqual(SpotlightEntrance.infoDelay, 1.3)
        XCTAssertEqual(SpotlightEntrance.infoFade, 0.7)
        XCTAssertEqual(SpotlightEntrance.infoLift, 40)
        XCTAssertEqual(SpotlightEntrance.infoLiftDuration, 0.8)
        XCTAssertEqual(SpotlightEntrance.titleDelay, 2.0)
    }
    func testFlightEasesOutAndFadesOnItsOwnClock() throws {
        let flight = try XCTUnwrap(SpotlightEntrance.flights(tiles: [80...254], rowWidth: row)[0])
        XCTAssertEqual(flight.move(at: 0), 0)
        XCTAssertEqual(flight.move(at: 0.45), 1 - 0.125, accuracy: 0.0001, "cubic out at half time")
        XCTAssertEqual(flight.move(at: 0.9), 1)
        XCTAssertEqual(flight.move(at: 2), 1)
        XCTAssertEqual(flight.opacity(at: 0.25), 0.5, accuracy: 0.0001, "linear fade")
        XCTAssertEqual(flight.opacity(at: 0.5), 1)
        XCTAssertEqual(flight.length, 0.9)
    }

    func testFadeOnlyFlightNeverMoves() throws {
        let flights = SpotlightEntrance.flights(tiles: [1800...1974], rowWidth: row)
        let late = try XCTUnwrap(flights[0])
        XCTAssertEqual(late.move(at: 0), 1)
        XCTAssertEqual(late.length, 0.4)
    }

    func testInfoRisesFortyUnitsAfterTheBackground() {
        let info = SpotlightEntrance.info
        XCTAssertEqual(info.delay, 1.3)
        XCTAssertEqual(info.fromY, 40)
        XCTAssertEqual(info.fromX, 0)
        XCTAssertEqual(info.fromScale, 1)
        XCTAssertEqual(info.duration, 0.8)
        XCTAssertEqual(info.fadeDuration, 0.7)
    }

    func testEmptyMessageComesJustAfterTheLastTile() {
        let flights = SpotlightEntrance.flights(tiles: tiles(2), rowWidth: row)
        let message = SpotlightEntrance.message(after: flights)
        XCTAssertEqual(message.delay, 0.6 + 2 * 0.06 + 0.25, accuracy: 0.0001)
        XCTAssertTrue(message.fadesOnly)
        XCTAssertEqual(SpotlightEntrance.message(after: []).delay, 0.85, accuracy: 0.0001)
    }

    func testEntranceEndsWhenEverythingIsIn() {
        // Ten tiles land at 2.04 s; the info is in at 2.1 s.
        let flights = SpotlightEntrance.flights(tiles: tiles(10, from: 0), rowWidth: 2000)
        XCTAssertEqual(SpotlightEntrance.end(of: flights), 2.1, accuracy: 0.0001)
        // Twenty tiles land at 0.6 + 19 × 0.06 + 0.9 = 2.64 s.
        let many = SpotlightEntrance.flights(tiles: tiles(20, from: 0), rowWidth: 4000)
        XCTAssertEqual(SpotlightEntrance.end(of: many), 2.64, accuracy: 0.0001)
    }
}
