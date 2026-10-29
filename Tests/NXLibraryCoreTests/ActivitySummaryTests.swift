import XCTest
@testable import NXLibraryCore

final class ActivitySummaryTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1 // Sunday: the summary must still use Monday.
        return c
    }()

    /// Wednesday 2026-10-28 12:00 UTC; the week is Mon 26 – Sun 1 Nov.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: month,
                                           day: day, hour: hour, minute: minute))!
    }
    private var now: Date { date(28, 12) }

    private func session(_ game: UUID, _ start: Date, _ end: Date?) -> PlaySession {
        PlaySession(gameID: game, titleID: "t", bundleID: nil, startedAt: start, endedAt: end,
                    lastHeartbeatAt: end ?? start)
    }

    func testWeekTotalsAndPerDay() {
        let g = UUID()
        let s = [session(g, date(26, 10), date(26, 11)),          // Mon 1h
                 session(g, date(28, 9), date(28, 9, 30)),        // Wed 30m
                 session(g, date(25, 10), date(25, 12))]          // Sun last week: ignored
        let r = Activity.summary(sessions: s, now: now, calendar: calendar)
        XCTAssertEqual(r.perDay, [3600, 0, 1800, 0, 0, 0, 0])
        XCTAssertEqual(r.thisWeek, 5400)
    }

    func testSessionAcrossMidnightSplits() {
        let g = UUID()
        let s = [session(g, date(26, 23), date(27, 1))]
        let r = Activity.summary(sessions: s, now: now, calendar: calendar)
        XCTAssertEqual(r.perDay, [3600, 3600, 0, 0, 0, 0, 0])
        XCTAssertEqual(r.thisWeek, 7200)
    }

    func testRunningSessionCountsToNow() {
        let g = UUID()
        let r = Activity.summary(sessions: [session(g, date(28, 10), nil)], now: now, calendar: calendar)
        XCTAssertEqual(r.perDay[2], 7200)
        XCTAssertEqual(r.thisWeek, 7200)
        XCTAssertEqual(r.topGames, [g])
    }

    func testTopGamesOrderedAndCapped() {
        let ids = (0..<8).map { _ in UUID() }
        var s: [PlaySession] = []
        for (i, id) in ids.enumerated() {
            s.append(session(id, date(26, 1), date(26, 1, 10 + i))) // later ids longer
        }
        let r = Activity.summary(sessions: s, now: now, calendar: calendar)
        XCTAssertEqual(r.topGames, Array(ids.reversed().prefix(6)))
        XCTAssertEqual(Activity.summary(sessions: [], now: now, calendar: calendar),
                       ActivitySummary())
    }
}
