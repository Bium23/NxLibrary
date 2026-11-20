import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class CheatStatusTests: XCTestCase {
    private func status(commit: String? = "abc", build: String? = "B424BE150A8E7D78", tid: String? = "0100000000010000",
                        ancestor: Bool? = true) -> CheatStatus {
        CheatStatus.of(engineCommit: commit, buildID: build, titleID: tid, isAncestor: { _ in ancestor })
    }

    func testRebuildWhenCommitOlderOrUnknown() {
        for s in [status(ancestor: false), status(ancestor: nil), status(commit: nil), status(build: nil), status(tid: nil)] {
            guard case .needsRebuild(let why) = s else { return XCTFail("\(s)") }
            XCTAssertFalse(why.isEmpty)
        }
    }

    func testReadyWhenAncestor() {
        XCTAssertEqual(status(), .ready)
    }

    private func state(file: String? = "[A]\n04000000 00004000 00000001\n[B]\n04000000 00004004 00000001\n[C]\n04000000 00004008 00000001\n{M}\n04000000 0000400C 00000001\n",
                       on: Set<String> = [], master: Bool = true) -> CheatState {
        CheatState(file: file.map { CheatFile.parse($0) }, enabled: on, hasEnabledFile: true, masterOn: master,
                   safeModePending: false, otherBuilds: [])
    }

    func testRowValues() {
        XCTAssertEqual(CheatStatus.rowValue(.needsRebuild("x"), state: nil), "Rebuild")
        XCTAssertEqual(CheatStatus.rowValue(.ready, state: state(file: nil)), "None")
        XCTAssertEqual(CheatStatus.rowValue(.ready, state: state(on: ["A"], master: false)), "Off")
        XCTAssertEqual(CheatStatus.rowValue(.ready, state: state(on: ["A", "B", "C"])), "3 on")
        XCTAssertEqual(CheatStatus.rowValue(.ready, state: state()), "0 on")
        XCTAssertEqual(CheatStatus.rowValue(.ready, state: nil), "None")
    }

    func testDetailLabelNeedsMasterAndASwitch() {
        XCTAssertFalse(CheatStatus.showsDetailLabel(.ready, state: state()), "masters alone do not count")
        XCTAssertTrue(CheatStatus.showsDetailLabel(.ready, state: state(on: ["A"])))
        XCTAssertFalse(CheatStatus.showsDetailLabel(.ready, state: state(on: ["A"], master: false)))
        XCTAssertFalse(CheatStatus.showsDetailLabel(.needsRebuild("x"), state: state(on: ["A"])))
    }

    /// Called from the ancestry's background task; the test reads it only after that task ends.
    private final class FakeGit: CommandRunning, @unchecked Sendable {
        var status: Int32 = 0
        var calls = 0
        var ranOnMainThread = false
        func run(_ executable: URL, _ arguments: [String], environment: [String: String]?,
                 currentDirectory: URL?) throws -> CommandResult {
            calls += 1
            ranOnMainThread = ranOnMainThread || Thread.isMainThread
            XCTAssertEqual(executable.path, "/usr/bin/git")
            XCTAssertEqual(Array(arguments.suffix(3)), ["--is-ancestor", "ef9", "c1"])
            return CommandResult(status: status, stdout: "", stderr: "")
        }
    }

    func testEngineAncestryParsesStatusAndCaches() async {
        let git = FakeGit()
        let ancestry = EngineAncestry(runner: git, engineFolder: URL(fileURLWithPath: "/tmp/nxnative"))
        let first = await ancestry.answer("ef9", in: "c1")
        let second = await ancestry.answer("ef9", in: "c1")
        XCTAssertEqual(first, true)
        XCTAssertEqual(second, true)
        XCTAssertEqual(git.calls, 1, "cached per commit")
        for (code, expected) in [(Int32(1), false as Bool?), (128, nil)] {
            let other = FakeGit(); other.status = code
            let answer = await EngineAncestry(runner: other, engineFolder: URL(fileURLWithPath: "/tmp")).answer("ef9", in: "c1")
            XCTAssertEqual(answer, expected)
        }
    }

    /// Game options and the Cheats panel open inside a SwiftUI update: git must not run on the main thread there.
    @MainActor
    func testEngineAncestryAsksGitOffTheMainThread() async {
        let git = FakeGit()
        let ancestry = EngineAncestry(runner: git, engineFolder: URL(fileURLWithPath: "/tmp/nxnative"))
        let answer = await ancestry.answer("ef9", in: "c1")
        XCTAssertEqual(answer, true)
        XCTAssertEqual(git.calls, 1)
        XCTAssertFalse(git.ranOnMainThread)
    }

    func testEngineAncestryKeptAnswerNeverRunsGit() async {
        let git = FakeGit(); git.status = 128
        let ancestry = EngineAncestry(runner: git, engineFolder: URL(fileURLWithPath: "/tmp/nxnative"))
        XCTAssertTrue(ancestry.keptAnswer("ef9", in: "c1") == nil, "not asked yet")
        XCTAssertEqual(git.calls, 0)
        _ = await ancestry.answer("ef9", in: "c1")
        XCTAssertEqual(ancestry.keptAnswer("ef9", in: "c1"), .some(nil), "asked; git could not tell")
        XCTAssertEqual(git.calls, 1)
    }

    func testCheatsCommitIsTheEngineFeature() {
        XCTAssertEqual(CheatStatus.cheatsCommit, "ef9f9bbaff5801dbd039bd10d4f2a9158edbae14")
    }
}
