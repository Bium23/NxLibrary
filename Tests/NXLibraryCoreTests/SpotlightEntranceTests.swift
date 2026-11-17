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

    func testSeleneValuesForTheFirstTile() throws {
        let flight = try XCTUnwrap(SpotlightEntrance.flights(tiles: [80...254], rowWidth: row).first ?? nil)
        XCTAssertEqual(flight.delay, 0.30, accuracy: 0.0001)
        XCTAssertEqual(flight.fromScale, 0.35, accuracy: 0.0001)
        XCTAssertEqual(flight.fromY, -18, accuracy: 0.0001)
        XCTAssertEqual(flight.duration, 0.65, accuracy: 0.0001)
        XCTAssertEqual(flight.fadeDuration, 0.35, accuracy: 0.0001)
        XCTAssertEqual(flight.fromX, (880 - 167) * 0.75, accuracy: 0.0001)
        XCTAssertFalse(flight.fadesOnly)
    }

    func testDelayGrowsByFortyFiveMillisecondsPerFlownTile() throws {
        let flights = SpotlightEntrance.flights(tiles: tiles(3), rowWidth: row)
        let third = try XCTUnwrap(flights[2])
        XCTAssertEqual(third.delay, 0.39, accuracy: 0.0001)
    }

    func testTilesLeftOfTheStageDoNotFly() throws {
        let flights = SpotlightEntrance.flights(tiles: [(-300)...(-126), 80...254], rowWidth: row)
        XCTAssertNil(flights[0])
        let first = try XCTUnwrap(flights[1])
        XCTAssertEqual(first.delay, 0.30, accuracy: 0.0001, "a tile off the left edge does not count")
    }

    func testTilesPastTheRightEdgeOnlyFade() throws {
        // Two on the stage, then fourteen past its right edge.
        let flights = SpotlightEntrance.flights(tiles: tiles(2, from: 1400) + tiles(14, from: 1800), rowWidth: row)
        let firstLate = try XCTUnwrap(flights[2])
        XCTAssertTrue(firstLate.fadesOnly)
        XCTAssertEqual(firstLate.delay, 0.30 + 2 * 0.045, accuracy: 0.0001)
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
        XCTAssertEqual(SpotlightEntrance.duration(of: flights), 0.30 + 9 * 0.045 + 0.65, accuracy: 0.0001)
        XCTAssertEqual(SpotlightEntrance.duration(of: []), 0)
    }

    func testPlaysOnlyOnFirstSpotlightWithoutReduceMotion() {
        XCTAssertTrue(SpotlightEntrance.plays(isFirstHome: true, route: .library, reduceMotion: false))
        XCTAssertFalse(SpotlightEntrance.plays(isFirstHome: true, route: .collection, reduceMotion: false))
        XCTAssertFalse(SpotlightEntrance.plays(isFirstHome: true, route: .library, reduceMotion: true))
        XCTAssertFalse(SpotlightEntrance.plays(isFirstHome: false, route: .library, reduceMotion: false))
    }

    func testInputLandsAWaitingOrPlayingEntrance() {
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

    func testInfoAndBackgroundUseSeleneTimes() {
        XCTAssertEqual(SpotlightEntrance.backgroundDuration, 0.9)
        XCTAssertEqual(SpotlightEntrance.infoDelay, 0.9)
        XCTAssertEqual(SpotlightEntrance.infoFade, 0.5)
        XCTAssertEqual(SpotlightEntrance.infoLift, 40)
        XCTAssertEqual(SpotlightEntrance.infoLiftDuration, 0.55)
    }
}
