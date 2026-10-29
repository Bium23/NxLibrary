import Foundation

/// This week's play time, for the Activity card and (later) its screen.
public struct ActivitySummary: Equatable {
    /// Total play time this week.
    public var thisWeek: TimeInterval
    /// Seven days, Monday through Sunday of the current week.
    public var perDay: [TimeInterval]
    /// Games by play time this week, most first, at most `maxTopGames`.
    public var topGames: [UUID]

    public static let maxTopGames = 6

    public init(thisWeek: TimeInterval = 0, perDay: [TimeInterval] = Array(repeating: 0, count: 7),
                topGames: [UUID] = []) {
        self.thisWeek = thisWeek
        self.perDay = perDay
        self.topGames = topGames
    }
}

public enum Activity {
    /// Sessions spanning midnight are split by day; a running session counts
    /// up to `now`; time outside the current week is ignored.
    public static func summary(sessions: [PlaySession], now: Date, calendar: Calendar) -> ActivitySummary {
        // The week is Monday-first regardless of the user's locale.
        var calendar = calendar
        calendar.firstWeekday = 2
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return ActivitySummary() }

        var days = [TimeInterval](repeating: 0, count: 7)
        var perGame: [UUID: TimeInterval] = [:]
        var firstSeen: [UUID: Int] = [:]
        for (order, session) in sessions.enumerated() {
            let start = max(session.startedAt, week.start)
            let end = min(session.endedAt ?? now, min(now, week.end))
            guard end > start else { continue }
            var cursor = start
            var total: TimeInterval = 0
            while cursor < end {
                let dayStart = calendar.startOfDay(for: cursor)
                let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? end
                let sliceEnd = min(nextDay, end)
                let index = calendar.dateComponents([.day], from: week.start, to: dayStart).day ?? 0
                let slice = sliceEnd.timeIntervalSince(cursor)
                if (0..<7).contains(index) { days[index] += slice }
                total += slice
                cursor = sliceEnd
            }
            perGame[session.gameID, default: 0] += total
            if firstSeen[session.gameID] == nil { firstSeen[session.gameID] = order }
        }
        let top = perGame.keys
            .sorted { a, b in
                perGame[a]! != perGame[b]! ? perGame[a]! > perGame[b]! : firstSeen[a]! < firstSeen[b]!
            }
            .prefix(ActivitySummary.maxTopGames)
        return ActivitySummary(thisWeek: days.reduce(0, +), perDay: days, topGames: Array(top))
    }
}
