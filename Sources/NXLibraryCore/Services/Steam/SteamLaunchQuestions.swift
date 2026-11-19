import Foundation

/// A launch Steam holds until the player answers it: Steam writes `GameAction [AppID <id>, …] : LaunchApp waiting
/// for user response to <question>` to its console log when a launch stops on a question (the game is playing on
/// another device, a cloud conflict, …), and a later `GameAction` line for that game once it moves on.
/// `ShowInterstitials` is a generic startup step that can use the same wording during a cold start.
/// Other questions count only after `grace`.
/// Only `GameAction` lines are read; nothing is kept but which games wait and since when.
public struct SteamLaunchQuestions: Equatable, Sendable {
    public static let grace: TimeInterval = 1

    /// Games whose launch waits on a question, with when Arcane first read it.
    private var pending: [UInt32: Date] = [:]

    public init() {}

    /// Reads complete log lines, in order (`SteamConsoleLog` keeps unfinished lines). `now` is when read.
    public mutating func read(_ text: String, now: Date) {
        for line in text.split(separator: "\n") { take(line, now: now) }
    }

    /// Steam started a new log: what the old one said no longer holds.
    public mutating func reset() {
        pending = [:]
    }

    /// Steam has been waiting on the player for this game's launch for at least `grace`.
    public func isAsking(appID: UInt32, now: Date) -> Bool {
        guard let since = pending[appID] else { return false }
        return now.timeIntervalSince(since) >= Self.grace
    }

    private static let action = "GameAction [AppID "
    private static let question = "LaunchApp waiting for user response to "

    private mutating func take(_ line: Substring, now: Date) {
        guard let start = line.range(of: Self.action)?.upperBound,
              let end = line[start...].firstIndex(where: { !$0.isNumber }),
              let appID = UInt32(line[start..<end]) else { return }
        guard let question = line[end...].range(of: Self.question),
              line[question.upperBound...].prefix(while: { !$0.isWhitespace }) != "ShowInterstitials" else {
            pending[appID] = nil
            return
        }
        if pending[appID] == nil { pending[appID] = now }
    }
}

/// Steam's console log (`<Steam>/logs/console_log.txt`), read from where the last read stopped, whole lines only: a
/// line Steam is still writing is read once it ends. Steam starts a new file each time it starts; a different or
/// shorter file is read again from the top.
public struct SteamConsoleLog: Sendable {
    public let fileURL: URL
    private var file: (number: UInt64, offset: UInt64)?

    public init(steamRoot: URL) {
        fileURL = steamRoot.appendingPathComponent("logs/console_log.txt")
    }

    /// The whole lines written since the last read, or nil without a log. `isNewFile` on the first read, for a new
    /// file and when more than `limit` bytes arrived at once: only the last `limit` bytes are read then, from their
    /// first whole line, and what came before is lost.
    public mutating func readNew(limit: Int = 1 << 20) -> (text: String, isNewFile: Bool)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let number = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        let limit = UInt64(max(limit, 1))
        var start: UInt64 = 0
        var isNewFile = true
        if let file, file.number == number, file.offset <= size {
            start = file.offset
            isNewFile = false
        }
        var cut = false
        if size - start > limit {
            start = size - limit
            cut = true
            isNewFile = true
        }
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.read(upToCount: Int(size - start)) ?? Data() else { return nil }
        let newline = UInt8(ascii: "\n")
        var lines = data[...]
        // A cut first line starts after its newline.
        if cut, start > 0 {
            lines = lines.firstIndex(of: newline).map { lines[lines.index(after: $0)...] } ?? lines[lines.endIndex...]
        }
        let end = lines.lastIndex(of: newline).map { lines.index(after: $0) } ?? lines.startIndex
        lines = lines[..<end]
        self.file = (number, start + UInt64(end - data.startIndex))
        return (String(decoding: lines, as: UTF8.self), isNewFile)
    }
}

/// Watches one Play's launch for a question in Steam's log: reads the log (from its last megabyte the first time,
/// so a question still open from an earlier Play counts) and says when Steam waits on the player.
public struct SteamLaunchQuestionWatch: Sendable {
    public let appID: UInt32
    private var log: SteamConsoleLog
    private var questions = SteamLaunchQuestions()

    public init(appID: UInt32, steamRoot: URL) {
        self.appID = appID
        log = SteamConsoleLog(steamRoot: steamRoot)
    }

    /// Reads what Steam wrote since the last look; true once Steam waits on the player for this game.
    public mutating func look(now: Date) -> Bool {
        if let new = log.readNew() {
            if new.isNewFile { questions.reset() }
            questions.read(new.text, now: now)
        }
        return questions.isAsking(appID: appID, now: now)
    }
}
