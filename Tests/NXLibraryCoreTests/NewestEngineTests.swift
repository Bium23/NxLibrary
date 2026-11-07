import XCTest
@testable import NXLibraryCore

final class NewestEngineTests: XCTestCase {
    private let pin = "4a0551e4b9abc75ea736006e4dbd30fcac0d03a4"
    private let main = "9c1d2e7f00000000000000000000000000000000"
    private let repo = URL(fileURLWithPath: "/Users/a b/nxnative")

    private func lock(_ metal: String) -> String {
        "# Translation chain tool fingerprints\nspirv-cross\te37945d8e441d34d\n"
            + "metal_macosx\tApple metal version \(metal) (metalfe-\(metal).4)\n"
            + "metal_iphoneos\tApple metal version \(metal) (metalfe-\(metal).4)\n"
    }

    /// Answers git by its subcommand and records every call.
    private final class FakeGit: CommandRunning {
        var answers: [String: CommandResult] = [:]
        var calls: [[String]] = []

        func run(_ executable: URL, _ arguments: [String], environment: [String: String]?,
                 currentDirectory: URL?) throws -> CommandResult {
            calls.append(arguments)
            let subcommand = arguments.count > 2 ? arguments[2] : ""
            return answers[subcommand] ?? CommandResult(status: 0, stdout: "", stderr: "")
        }

        var subcommands: [String] { calls.map { $0.count > 2 ? $0[2] : "" } }
    }

    // MARK: - Lock and readiness

    func testLockMetalReadsTheMacLine() {
        XCTAssertEqual(NewestEngine.lockMetal(lock("32023.922")), "32023.922")
        XCTAssertNil(NewestEngine.lockMetal("spirv-cross\te37945d8e441d34d\n"))
    }

    func testMainWithTheTestedMetalIsUsable() {
        XCTAssertEqual(NewestEngine.readiness(newestLock: lock("32023.922"), testedMetal: "32023.922"), .usable)
    }

    func testMainWithAnotherMetalNeedsANewerApp() {
        XCTAssertEqual(NewestEngine.readiness(newestLock: lock("32024.100"), testedMetal: "32023.922"),
                       .needsNewerApp(metal: "32024.100"))
        XCTAssertEqual(NewestEngineCopy.needsNewerApp(metal: "32024.100"),
                       "The newest nxnative needs Metal 32024.100, so it needs a newer NX Library.")
    }

    func testAnUnreadableLockIsUnknown() {
        XCTAssertEqual(NewestEngine.readiness(newestLock: nil, testedMetal: "32023.922"), .unknown)
        XCTAssertEqual(NewestEngine.readiness(newestLock: lock("32023.922"), testedMetal: nil), .unknown)
    }

    func testLockURLIsTheRawFileOfThatCommitOnly() {
        XCTAssertEqual(NewestEngine.lockURL(commit: main)?.absoluteString,
                       "https://raw.githubusercontent.com/seedds/nxnative/\(main)/dm/gfx/tools/dmsh_chain.lock")
        XCTAssertNil(NewestEngine.lockURL(commit: "main/../x"))
        XCTAssertNil(NewestEngine.lockURL(commit: ""))
    }

    func testFetchLockReturnsTheBodyOnlyOnSuccess() async {
        let client = UpstreamCheckerTests.FakeClient()
        let url = NewestEngine.lockURL(commit: main)!
        client.result = .success((Data(lock("32023.922").utf8),
                                  HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        let body = await NewestEngine.fetchLock(commit: main, client: client)
        XCTAssertEqual(body.flatMap(NewestEngine.lockMetal), "32023.922")
        XCTAssertEqual(client.request?.url, url)

        client.result = .success((Data("Not Found".utf8),
                                  HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!))
        let missing = await NewestEngine.fetchLock(commit: main, client: client)
        XCTAssertNil(missing)
    }

    // MARK: - When a choice holds

    func testAChoiceHoldsWhileTheCheckoutIsAtItAndThePinHasNotCaughtUp() {
        let choice = NewestEngineChoice(commit: main, aheadBy: 12, turnedOnOverride: true)
        XCTAssertTrue(NewestEngine.keeps(choice, head: main, pinned: pin, includedInPin: false))
        XCTAssertTrue(NewestEngine.keeps(choice, head: main, pinned: pin, includedInPin: nil))
        XCTAssertFalse(NewestEngine.keeps(choice, head: pin, pinned: pin, includedInPin: false), "moved by Setup or by hand")
        XCTAssertFalse(NewestEngine.keeps(choice, head: nil, pinned: pin, includedInPin: nil), "no checkout")
        XCTAssertFalse(NewestEngine.keeps(choice, head: main, pinned: pin, includedInPin: true), "an update tested it")
        XCTAssertFalse(NewestEngine.keeps(choice, head: main, pinned: main, includedInPin: true), "it is the pin now")
    }

    func testAChoiceSurvivesBeingSaved() throws {
        let choice = NewestEngineChoice(commit: main, aheadBy: 138, turnedOnOverride: true)
        let data = try JSONEncoder().encode(choice)
        XCTAssertEqual(try JSONDecoder().decode(NewestEngineChoice.self, from: data), choice)
        XCTAssertEqual(choice.shortCommit, "9c1d2e7")
    }

    // MARK: - Row actions

    private let newer = "b7e3f0a100000000000000000000000000000000"

    func testWithoutAChoiceANewerMainOffersUseNewest() {
        XCTAssertEqual(NewestEngine.actions(choice: nil, main: main, readiness: .usable), [.useNewest])
        XCTAssertEqual(NewestEngine.actions(choice: nil, main: main, readiness: nil), [.useNewest], "lock still loading")
        XCTAssertEqual(NewestEngine.actions(choice: nil, main: nil, readiness: nil), [], "main is the pin")
        XCTAssertEqual(NewestEngine.actions(choice: nil, main: main, readiness: .needsNewerApp(metal: "32100.1")), [])
    }

    func testAChoiceBehindMainOffersUpdateBesideBackToTested() {
        let choice = NewestEngineChoice(commit: main, aheadBy: 12, turnedOnOverride: true)
        XCTAssertEqual(NewestEngine.actions(choice: choice, main: newer, readiness: .usable), [.update, .backToTested])
        XCTAssertEqual(NewestEngine.actions(choice: choice, main: newer, readiness: nil), [.update, .backToTested])
    }

    func testAChoiceAtMainOrBeforeAnotherMetalOffersOnlyBackToTested() {
        let choice = NewestEngineChoice(commit: main, aheadBy: 12, turnedOnOverride: true)
        XCTAssertEqual(NewestEngine.actions(choice: choice, main: main, readiness: .usable), [.backToTested])
        XCTAssertEqual(NewestEngine.actions(choice: choice, main: nil, readiness: nil), [.backToTested], "not checked")
        XCTAssertEqual(NewestEngine.actions(choice: choice, main: newer, readiness: .needsNewerApp(metal: "32100.1")),
                       [.backToTested])
    }

    func testTheUpdateSentenceCountsCommitsPastTheOneInUse() {
        let choice = NewestEngineChoice(commit: main, aheadBy: 12, turnedOnOverride: true)
        XCTAssertEqual(NewestEngineCopy.update(choice: choice, main: newer, aheadBy: 23),
                       "main has moved on: b7e3f0a, 11 commits newer.")
        XCTAssertEqual(NewestEngineCopy.update(choice: choice, main: newer, aheadBy: 13),
                       "main has moved on: b7e3f0a, 1 commit newer.")
        XCTAssertEqual(NewestEngineCopy.update(choice: choice, main: newer, aheadBy: 12),
                       "main has moved on: b7e3f0a.", "history rewritten: no count")
    }

    func testTheControllerUpdatesWithAAndGoesBackToTestedWithY() {
        let both = NewestEngine.controller([.update, .backToTested])
        XCTAssertEqual(both?.primary, .update)
        XCTAssertEqual(both?.secondary, .backToTested)
        XCTAssertEqual(NewestEngine.controller([.backToTested])?.primary, .backToTested)
        XCTAssertNil(NewestEngine.controller([.backToTested])?.secondary)
        XCTAssertEqual(NewestEngine.controller([.useNewest])?.primary, .useNewest)
        XCTAssertNil(NewestEngine.controller([]))
    }

    // MARK: - Commit marks

    private func commits(_ shas: [String]) -> [UpstreamCommit] {
        shas.map { UpstreamCommit(sha: $0, author: "seedds", date: "", subject: $0) }
    }

    func testCommitsAboveTheOneInUseAreNewAndItIsInUse() {
        let list = commits(["c3", "c2", "c1", "c0"])
        XCTAssertEqual(NewestEngine.marks(list, inUse: "c1"), ["c3": .new, "c2": .new, "c1": .inUse])
    }

    func testTheNewestCommitInUseHasNothingNewAbove() {
        XCTAssertEqual(NewestEngine.marks(commits(["c3", "c2"]), inUse: "c3"), ["c3": .inUse])
    }

    func testNoMarksOnTheTestedEngineOrForACommitNotListed() {
        XCTAssertEqual(NewestEngine.marks(commits(["c3", "c2"]), inUse: nil), [:], "tested engine")
        XCTAssertEqual(NewestEngine.marks(commits(["c3", "c2"]), inUse: "zz"), [:], "history rewritten")
    }

    // MARK: - Switching

    func testUseNewestFetchesReadsTheLockAndSwitches() throws {
        let git = FakeGit()
        git.answers["show"] = CommandResult(status: 0, stdout: lock("32023.922"), stderr: "")
        try NewestEngineSwitcher(repo: repo, runner: git).useNewest(commit: main, testedMetal: "32023.922")
        XCTAssertEqual(git.subcommands, ["status", "fetch", "show", "checkout"])
        XCTAssertEqual(git.calls[2], ["-C", repo.path, "show", "\(main):dm/gfx/tools/dmsh_chain.lock"])
        XCTAssertEqual(git.calls.last, ["-C", repo.path, "checkout", "--quiet", "--detach", main])
    }

    func testUseNewestRefusesAnotherMetalWithoutTouchingTheCheckout() {
        let git = FakeGit()
        git.answers["show"] = CommandResult(status: 0, stdout: lock("32024.100"), stderr: "")
        XCTAssertThrowsError(try NewestEngineSwitcher(repo: repo, runner: git).useNewest(commit: main, testedMetal: "32023.922")) {
            XCTAssertEqual($0 as? NewestEngineError, .needsNewerApp(metal: "32024.100"))
        }
        XCTAssertFalse(git.subcommands.contains("checkout"))
    }

    func testChangedFilesAreNeverTouched() {
        let git = FakeGit()
        git.answers["status"] = CommandResult(status: 0, stdout: " M dm/host/front_mac.m\n", stderr: "")
        XCTAssertThrowsError(try NewestEngineSwitcher(repo: repo, runner: git).useNewest(commit: main, testedMetal: "32023.922")) {
            XCTAssertEqual($0 as? NewestEngineError, .localChanges)
        }
        XCTAssertThrowsError(try NewestEngineSwitcher(repo: repo, runner: git).useTested(pinned: pin)) {
            XCTAssertEqual($0 as? NewestEngineError, .localChanges)
        }
        XCTAssertEqual(git.subcommands, ["status", "status"])
    }

    func testBuildOutputDoesNotCountAsAChange() throws {
        let git = FakeGit()
        git.answers["status"] = CommandResult(status: 0, stdout: "?? dm/games/X/_build/\n?? .venv/\n", stderr: "")
        git.answers["show"] = CommandResult(status: 0, stdout: lock("32023.922"), stderr: "")
        XCTAssertNoThrow(try NewestEngineSwitcher(repo: repo, runner: git).useNewest(commit: main, testedMetal: "32023.922"))
    }

    func testAFailedDownloadSaysSo() {
        let git = FakeGit()
        git.answers["fetch"] = CommandResult(status: 128, stdout: "", stderr: "fatal: unable to access")
        XCTAssertThrowsError(try NewestEngineSwitcher(repo: repo, runner: git).useNewest(commit: main, testedMetal: "32023.922")) {
            XCTAssertEqual($0 as? NewestEngineError, .downloadFailed)
        }
    }

    func testBackToTestedChecksOutThePinAndFetchesOnlyWhenMissing() throws {
        let present = FakeGit()
        try NewestEngineSwitcher(repo: repo, runner: present).useTested(pinned: pin)
        XCTAssertEqual(present.subcommands, ["status", "cat-file", "checkout"])
        XCTAssertEqual(present.calls.last, ["-C", repo.path, "checkout", "--quiet", "--detach", pin])

        let missing = FakeGit()
        missing.answers["cat-file"] = CommandResult(status: 128, stdout: "", stderr: "")
        try NewestEngineSwitcher(repo: repo, runner: missing).useTested(pinned: pin)
        XCTAssertEqual(missing.subcommands, ["status", "cat-file", "fetch", "checkout"])
    }

    func testIsIncludedReadsMergeBase() {
        let git = FakeGit()
        let switcher = NewestEngineSwitcher(repo: repo, runner: git)
        XCTAssertEqual(switcher.isIncluded(main, in: pin), true)
        git.answers["merge-base"] = CommandResult(status: 1, stdout: "", stderr: "")
        XCTAssertEqual(switcher.isIncluded(main, in: pin), false)
        git.answers["merge-base"] = CommandResult(status: 128, stdout: "", stderr: "")
        XCTAssertNil(switcher.isIncluded(main, in: pin))
        XCTAssertEqual(git.calls[0], ["-C", repo.path, "merge-base", "--is-ancestor", main, pin])
    }

    // MARK: - Gate

    private func report(ok: Bool) -> CompatibilityReport {
        CompatibilityReport(ok: ok, checks: [CompatibilityCheck(id: "commit", title: "Engine commit",
                                                                status: ok ? .pass : .block, detail: "")],
                            metal: .same)
    }

    func testThePassingNewestEngineIsNeverCalledCertified() {
        let summary = ToolchainGateCopy.summary(report: report(ok: true), overrideOn: true, newest: true)
        XCTAssertEqual(summary.label, "Newest engine")
        XCTAssertEqual(summary.tone, .newest)
        XCTAssertEqual(summary.buildHint, "")
        XCTAssertEqual(ToolchainGateCopy.summary(report: report(ok: true), overrideOn: false).label, "Certified")
    }

    func testABlockedNewestEngineStillSaysWhy() {
        XCTAssertEqual(ToolchainGateCopy.summary(report: report(ok: false), overrideOn: true, newest: true).tone, .override)
    }

    func testTheOverrideStaysOnWhileTheNewestEngineIsInUse() {
        XCTAssertFalse(ToolchainGateCopy.canChangeOverride(certified: true, overrideOn: true, locked: false, newest: true))
        XCTAssertTrue(ToolchainGateCopy.canChangeOverride(certified: true, overrideOn: true, locked: false))
    }

    // MARK: - Setup

    private func facts(head: String, choice: NewestEngineChoice?) -> SetupFacts {
        var facts = SetupFacts(xcodeStatus: 0, metalVersion: "32023.922", certifiedMetal: "32023.922", allowUntested: true,
                               dotnetSDKs: ["10.0.401 [/usr/local/share/dotnet/sdk]"],
                               engine: .checkout(head: head, dirty: false), engineFolder: repo, pinnedCommit: pin,
                               runtimeProblem: nil, keys: nil, keysError: nil, libraryReadable: true,
                               engineBehind: false)
        facts.newestEngine = choice
        return facts
    }

    func testSetupShowsTheChosenEngineAsReadyButUntested() {
        let choice = NewestEngineChoice(commit: main, aheadBy: 12, turnedOnOverride: true)
        let card = SetupCheck.items(from: facts(head: main, choice: choice)).first { $0.id == .engine }!
        XCTAssertEqual(card.state, .ready)
        XCTAssertTrue(card.isUntested)
        XCTAssertEqual(card.chip, "NEWEST ENGINE")
        XCTAssertEqual(card.actionTitle, "Back to tested")
        XCTAssertEqual(card.about, NewestEngineCopy.note)
        XCTAssertEqual(card.detail, "At 9c1d2e7, 12 commits ahead of the tested 4a0551e, chosen in Settings → Engine.")
        XCTAssertEqual(SetupActions.engineAction(for: .checkout(head: main, dirty: false), pinned: pin, newest: main), .none)
    }

    func testAnUnchosenNewerCheckoutIsStillAnotherVersion() {
        let card = SetupCheck.items(from: facts(head: main, choice: nil)).first { $0.id == .engine }!
        XCTAssertEqual(card.chip, "OTHER VERSION")
        XCTAssertFalse(card.isUntested)
        XCTAssertEqual(SetupActions.engineAction(for: .checkout(head: main, dirty: false), pinned: pin), .checkout)
    }

    func testAFreshInstallStillClonesTheTestedPin() {
        XCTAssertEqual(SetupActions.engineAction(for: .missing, pinned: pin, newest: main), .clone)
        XCTAssertEqual(SetupActions.gitCommands(for: .clone, folder: repo, pinned: pin).last,
                       ["-C", repo.path, "checkout", "--detach", pin])
    }

    // MARK: - Copy

    func testTheSentenceIsTheOneAgreed() {
        XCTAssertEqual(NewestEngineCopy.note,
                       "Newest nxnative, not yet tested by NX Library. It usually works, but something may not. "
                       + "Its new features reach NX Library in a future version.")
        XCTAssertEqual(NewestEngineCopy.ahead(1), "1 commit ahead")
        XCTAssertEqual(NewestEngineCopy.offer(commit: main, aheadBy: 138),
                       "Build with nxnative main (9c1d2e7, 138 commits ahead) before NX Library has tested it.")
    }
}
