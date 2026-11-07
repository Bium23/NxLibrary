import XCTest
@testable import NXLibraryCore

final class SessionSummaryTests: XCTestCase {
    private let game = PortedGame(name: "Zelda",
                                  url: URL(fileURLWithPath: "/tmp/Zelda.app"),
                                  platform: .macApp,
                                  sizeBytes: 1,
                                  modificationDate: Date(timeIntervalSince1970: 0),
                                  bundleId: "org.nxnative.0100000000010000",
                                  titleId: "0100000000010000")

    private func session(lasting seconds: TimeInterval?) -> PlaySession {
        let start = Date(timeIntervalSince1970: 1_000)
        return PlaySession(gameID: game.id, titleID: "0100000000010000", bundleID: game.bundleId,
                           startedAt: start, endedAt: seconds.map { start.addingTimeInterval($0) },
                           lastHeartbeatAt: start)
    }

    func testAnEndedSessionGivesTheGameThisSessionAndTotal() throws {
        let summary = try XCTUnwrap(SessionSummary(session: session(lasting: 4_320), game: game, total: 122_700))
        XCTAssertEqual(summary.gameID, game.id)
        XCTAssertEqual(summary.gameName, "Zelda")
        XCTAssertEqual(summary.thisSession, "1h 12m")
        XCTAssertEqual(summary.total, "34h 5m")
    }

    func testTheTotalReadsLikeTheGameInfo() throws {
        let summary = try XCTUnwrap(SessionSummary(session: session(lasting: 600), game: game, total: 122_700))
        XCTAssertEqual(summary.total, LibraryPresentation.duration(122_700))
        XCTAssertEqual(summary.thisSession, "10m")
    }

    func testUnderAMinuteSaysSo() throws {
        let summary = try XCTUnwrap(SessionSummary(session: session(lasting: 42), game: game, total: 42))
        XCTAssertEqual(summary.thisSession, "Less than a minute")
        XCTAssertEqual(summary.total, "Less than a minute")
    }

    func testSessionsShorterThanTenSecondsShowNoCard() {
        XCTAssertNil(SessionSummary(session: session(lasting: 9), game: game, total: 9))
        XCTAssertNotNil(SessionSummary(session: session(lasting: 10), game: game, total: 10))
    }

    func testARunningSessionShowsNoCard() {
        XCTAssertNil(SessionSummary(session: session(lasting: nil), game: game, total: 3_600))
    }

    func testAnotherGamesSessionShowsNoCard() {
        let other = PlaySession(gameID: UUID(), titleID: "x", bundleID: nil,
                                startedAt: Date(timeIntervalSince1970: 0),
                                endedAt: Date(timeIntervalSince1970: 600),
                                lastHeartbeatAt: Date(timeIntervalSince1970: 0))
        XCTAssertNil(SessionSummary(session: other, game: game, total: 600))
    }
}
