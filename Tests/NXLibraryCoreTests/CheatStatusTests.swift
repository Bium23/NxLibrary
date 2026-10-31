import XCTest
@testable import NXLibraryCore

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

    private final class FakeGit: CommandRunning {
        var status: Int32 = 0
        var calls = 0
        func run(_ executable: URL, _ arguments: [String], environment: [String: String]?,
                 currentDirectory: URL?) throws -> CommandResult {
            calls += 1
            XCTAssertEqual(executable.path, "/usr/bin/git")
            XCTAssertEqual(Array(arguments.suffix(3)), ["--is-ancestor", "ef9", "c1"])
            return CommandResult(status: status, stdout: "", stderr: "")
        }
    }

    func testEngineAncestryParsesStatusAndCaches() {
        let git = FakeGit()
        let ancestry = EngineAncestry(runner: git, engineFolder: URL(fileURLWithPath: "/tmp/nxnative"))
        XCTAssertEqual(ancestry.contains("ef9", in: "c1"), true)
        XCTAssertEqual(ancestry.contains("ef9", in: "c1"), true)
        XCTAssertEqual(git.calls, 1, "cached per commit")
        for (code, answer) in [(Int32(1), false as Bool?), (128, nil)] {
            let other = FakeGit(); other.status = code
            XCTAssertEqual(EngineAncestry(runner: other, engineFolder: URL(fileURLWithPath: "/tmp")).contains("ef9", in: "c1"), answer)
        }
    }

    func testCheatsCommitIsTheEngineFeature() {
        XCTAssertEqual(CheatStatus.cheatsCommit, "ef9f9bbaff5801dbd039bd10d4f2a9158edbae14")
    }
}
