import XCTest
@testable import NXLibraryCore

final class SteamLaunchQuestionsTests: XCTestCase {
    private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
    private func line(_ app: UInt32 = 2141910, _ text: String) -> String {
        "[2026-11-14 18:03:08] GameAction [AppID \(app), ActionID 1] : LaunchApp \(text)\n"
    }
    private func waiting(_ app: UInt32 = 2141910, _ task: String = "KickingOtherSession") -> String {
        line(app, "waiting for user response to \(task) \"Game\"")
    }

    func testAQuestionAnsweredAtOnceIsNotAsking() {
        var questions = SteamLaunchQuestions()
        questions.read(waiting(2141910, "ShowInterstitials") + line(2141910, "continues with user response \"ShowInterstitials\""),
                       now: date(0))
        XCTAssertFalse(questions.isAsking(appID: 2141910, now: date(5)))
    }

    func testColdStartInterstitialDoesNotDismissTheCoverBeforeARealQuestion() {
        var questions = SteamLaunchQuestions()
        questions.read(line(2141910, "changed task to ShowInterstitials with \"\"")
                       + line(2141910, "waiting for user response to ShowInterstitials \"\""), now: date(7))
        XCTAssertFalse(questions.isAsking(appID: 2141910, now: date(9)))

        questions.read(waiting(), now: date(10))
        XCTAssertFalse(questions.isAsking(appID: 2141910, now: date(10.5)))
        XCTAssertTrue(questions.isAsking(appID: 2141910, now: date(11)))
    }

    func testAnOpenQuestionAsksOnceItOutlastsTheGrace() {
        var questions = SteamLaunchQuestions()
        questions.read(waiting(), now: date(10))
        XCTAssertFalse(questions.isAsking(appID: 2141910, now: date(10.5)))
        XCTAssertTrue(questions.isAsking(appID: 2141910, now: date(10 + SteamLaunchQuestions.grace)))
    }

    func testAnotherGamesQuestionIsNotOurs() {
        var questions = SteamLaunchQuestions()
        questions.read(waiting(440), now: date(0))
        XCTAssertFalse(questions.isAsking(appID: 2141910, now: date(5)))
        XCTAssertTrue(questions.isAsking(appID: 440, now: date(5)))
    }

    func testTheLaunchMovingOnClearsTheQuestion() {
        var questions = SteamLaunchQuestions()
        questions.read(waiting(), now: date(0))
        questions.read(line(2141910, "changed task to SynchronizingCloud with \"\""), now: date(3))
        XCTAssertFalse(questions.isAsking(appID: 2141910, now: date(5)))
    }

    func testAQuestionRepeatedKeepsWhenItWasFirstSeen() {
        var questions = SteamLaunchQuestions()
        questions.read(waiting(), now: date(0))
        questions.read(waiting(), now: date(0.9))
        XCTAssertTrue(questions.isAsking(appID: 2141910, now: date(1)))
    }

    func testOtherLinesAreIgnored() {
        var questions = SteamLaunchQuestions()
        questions.read("[2026-11-14 18:13:38] ExecuteSteamURL: \"steam://run/2141910\"\n"
                       + "waiting for user response to KickingOtherSession\n", now: date(0))
        XCTAssertFalse(questions.isAsking(appID: 2141910, now: date(5)))
    }

    func testResetForgetsEverything() {
        var questions = SteamLaunchQuestions()
        questions.read(waiting(), now: date(0))
        questions.read("[2026-11-14 18:03:09] GameAction [AppID 2141910, Act", now: date(0))
        questions.reset()
        XCTAssertFalse(questions.isAsking(appID: 2141910, now: date(5)))
        questions.read("ionID 1] : LaunchApp waiting for user response to X \"\"\n", now: date(5))
        XCTAssertFalse(questions.isAsking(appID: 2141910, now: date(9)), "the half line before the reset is gone")
    }

    /// Steam's own sequence for a game already playing elsewhere (console_log.txt, 14 Nov 2026).
    func testSteamsSequenceForASessionElsewhereAsks() {
        let log = """
        [2026-11-14 18:03:07] ExecuteSteamURL: "steam://run/2141910"
        [2026-11-14 18:03:07] GameAction [AppID 2141910, ActionID 1] : LaunchApp changed task to RunningInstallScript with ""
        [2026-11-14 18:03:07] GameAction [AppID 2141910, ActionID 1] : LaunchApp changed task to SynchronizingStats with ""
        [2026-11-14 18:03:07] CAPIJobRequestUserStats - Server response failed 2
        [2026-11-14 18:03:07] GameAction [AppID 2141910, ActionID 1] : LaunchApp changed task to ShowInterstitials with ""
        [2026-11-14 18:03:07] GameAction [AppID 2141910, ActionID 1] : LaunchApp waiting for user response to ShowInterstitials ""
        [2026-11-14 18:03:07] GameAction [AppID 2141910, ActionID 1] : LaunchApp continues with user response "ShowInterstitials"
        [2026-11-14 18:03:07] GameAction [AppID 2141910, ActionID 1] : LaunchApp changed task to SynchronizingControllerConfig with ""
        [2026-11-14 18:03:08] GameAction [AppID 2141910, ActionID 1] : LaunchApp changed task to KickingOtherSession with ""
        [2026-11-14 18:03:08] GameAction [AppID 2141910, ActionID 1] : LaunchApp waiting for user response to KickingOtherSession "DRAGON BALL: Sparking! ZERO"

        """
        var questions = SteamLaunchQuestions()
        questions.read(log, now: date(0))
        XCTAssertTrue(questions.isAsking(appID: 2141910, now: date(1)))
    }
}

final class SteamConsoleLogTests: XCTestCase {
    private var folder: URL!
    private var file: URL { folder.appendingPathComponent("logs/console_log.txt") }

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("SteamConsoleLog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("logs"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func append(_ text: String) throws {
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func testTheLogLivesInSteamsLogsFolder() {
        XCTAssertEqual(SteamConsoleLog(steamRoot: folder).fileURL, file)
    }

    func testAMissingLogReadsNothing() {
        var log = SteamConsoleLog(steamRoot: folder)
        XCTAssertNil(log.readNew())
    }

    func testTheFirstReadTakesTheFileThenOnlyWhatWasAdded() throws {
        try append("one\n")
        var log = SteamConsoleLog(steamRoot: folder)
        XCTAssertEqual(log.readNew()?.text, "one\n")
        XCTAssertEqual(log.readNew()?.isNewFile, false)
        XCTAssertEqual(log.readNew()?.text, "")
        try append("two\n")
        let next = log.readNew()
        XCTAssertEqual(next?.text, "two\n")
        XCTAssertEqual(next?.isNewFile, false)
    }

    func testTheFirstReadIsANewFile() throws {
        try append("one\n")
        var log = SteamConsoleLog(steamRoot: folder)
        XCTAssertEqual(log.readNew()?.isNewFile, true)
    }

    func testANewFileFromAStartingSteamIsReadFromTheTop() throws {
        try append("an old session that ran long\n")
        var log = SteamConsoleLog(steamRoot: folder)
        _ = log.readNew()
        try FileManager.default.removeItem(at: file)
        try append("new\n")
        let next = log.readNew()
        XCTAssertEqual(next?.text, "new\n")
        XCTAssertEqual(next?.isNewFile, true)
    }

    func testAShorterFileIsANewFile() throws {
        try append("an old session that ran long\n")
        var log = SteamConsoleLog(steamRoot: folder)
        _ = log.readNew()
        try Data("new\n".utf8).write(to: file)
        XCTAssertEqual(log.readNew()?.isNewFile, true)
    }

    /// A line Steam is still writing is read once it ends, so a character cut between two reads stays whole.
    func testACharacterCutBetweenReadsStaysWhole() throws {
        let line = Data("GameAction \"Pokémon\"\n".utf8)
        let cut = line.firstIndex(of: 0xC3)! + 1
        try line[..<cut].write(to: file)
        var log = SteamConsoleLog(steamRoot: folder)
        XCTAssertEqual(log.readNew()?.text, "")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: line[cut...]); try handle.close()
        XCTAssertEqual(log.readNew()?.text, "GameAction \"Pokémon\"\n")
    }

    func testAnUnfinishedLineWaitsForItsEnd() throws {
        try append("one\ntw")
        var log = SteamConsoleLog(steamRoot: folder)
        XCTAssertEqual(log.readNew()?.text, "one\n")
        try append("o\n")
        XCTAssertEqual(log.readNew()?.text, "two\n")
    }

    func testOnlyTheEndOfALongFileIsReadFromItsFirstWholeLine() throws {
        try append("aaaaaaaaaa\nbbbbbbbbbb\ncccc\n")
        var log = SteamConsoleLog(steamRoot: folder)
        XCTAssertEqual(log.readNew(limit: 10)?.text, "cccc\n")
    }
}

final class SteamLaunchQuestionWatchTests: XCTestCase {
    private var folder: URL!
    private var file: URL { folder.appendingPathComponent("logs/console_log.txt") }
    private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
    private let question = "[2026-11-14 18:03:08] GameAction [AppID 2141910, ActionID 1] : LaunchApp waiting for user response to KickingOtherSession \"Game\"\n"

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("SteamQuestionWatch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("logs"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    /// Steam asked before this Play and still waits: a new steam://run adds no GameAction line.
    func testAQuestionStillOpenFromAnEarlierPlayAsks() throws {
        try Data((question + "[2026-11-14 18:13:38] ExecuteSteamURL: \"steam://run/2141910\"\n").utf8).write(to: file)
        var watch = SteamLaunchQuestionWatch(appID: 2141910, steamRoot: folder)
        XCTAssertFalse(watch.look(now: date(0)))
        XCTAssertTrue(watch.look(now: date(1)))
    }

    func testAStartingSteamsNewLogForgetsTheOldQuestion() throws {
        try Data(question.utf8).write(to: file)
        var watch = SteamLaunchQuestionWatch(appID: 2141910, steamRoot: folder)
        _ = watch.look(now: date(0))
        try FileManager.default.removeItem(at: file)
        try Data("[2026-11-14 18:20:00] Console Log Start\n".utf8).write(to: file)
        XCTAssertFalse(watch.look(now: date(5)))
    }

    func testWithoutALogNothingAsks() {
        var watch = SteamLaunchQuestionWatch(appID: 2141910, steamRoot: folder)
        XCTAssertFalse(watch.look(now: date(5)))
    }
}
