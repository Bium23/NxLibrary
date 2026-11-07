import XCTest
@testable import NXLibraryCore

final class PortingFailureReasonTests: XCTestCase {
    /// One real line per table row, as the pinned engine prints it ("[RED] " + its BuildError text).
    static let engineLines: [(id: String, kind: PortingFailureReason.Kind, line: String)] = [
        ("rosetta.intel", .rosetta, "[RED] this Python (/usr/local/bin/python3) is an Intel one running under Rosetta, and the tools it starts would run as Intel code too: run the script with an arm64 Python"),
        ("translator.run", .translator, "[RED] the shader translator does not run (exit 1): it needs the .NET 10 runtime for this Mac's architecture"),
        ("translator.start", .translator, "[RED] the shader translator does not start ([Errno 2] No such file): /x/translator"),
        ("zbic.missing", .zbic, "[RED] main: ZBIC (zstd) segments need the zbic package (python3 -m pip install zbic)"),
        ("clt.selected", .cltSelected, "[RED] the selected developer folder is the Command Line Tools (/Library/Developer/CommandLineTools), which have no iOS SDK"),
        ("metal.other", .otherMetal, "[RED] this Mac's Metal compiler is not the one the shaders were tested with (dm/gfx/tools/dmsh_chain.lock): 32023.999"),
        ("shaders.regression", .shaderRegression, "[RED] 12 shaders that translated in b-abc fail in b-def: a change to the translation chain broke them"),
        ("nsp.damaged", .damagedNSP, "[RED] 3 files fail the NCA's hash check (an incomplete copy or a broken download); copy or download it again, or pass --allow-damaged"),
        ("nsp.tables", .damagedNSP, "[RED] the NSP is damaged: a filesystem's own tables fail the NCA's hash check, so --allow-damaged cannot read it either: an incomplete copy or a broken download, which a SHA-256 of each NCA shows (its file name is the hash's first 16 bytes); copy or download it again"),
        ("nsp.truncated", .damagedNSP, "[RED] truncated PFS0 header: Example.nsp"),
        ("files.format", .damagedNSP, "[RED] base: 3 file(s) whose bytes do not start as their names promise (a .zs file that is not a zstd stream), so the game files are damaged:\n  Model/a.zs (12,288 bytes, starts 00000000)\nPack again from a good copy of the game (--allow-damaged packs these files as they are)"),
        ("language.missing", .unknown, "[RED] the game has no ja (Japanese); its languages: en-US (American English), fr (French) (--language / LANGUAGE)"),
        ("arm32.program", .a32Program, "[RED] Mario Kart 8 Deluxe v0 (1.0.0) is a 32-bit ARM program, which nxnative does not run"),
        ("keys.missing", .keys, "[RED] no such file: /Users/x/prod.keys"),
        ("keys.tooOld", .keysTooOld, "[RED] Example.nsp: prod.keys has no key_area_key_application_14 (master key 14, which came with firmware 21.0.0): the keys are older than the game; dump prod.keys again from a console on firmware 21.0.0 or later"),
        ("keys.ticket", .keys, "[RED] Example.nsp: no title key for rights ID 00000000000000000000000000000000: the package has no common ticket for it"),
        ("games.several", .severalGames, "[RED] more than one game in the folder, keep one game per folder: 0100000000010000, 0100000000020000"),
        ("games.noTitleID", .noTitleID, "[RED] no game package with a readable content meta in /Users/x/Games/Foo"),
        ("disk.low", .diskFull, "[RED] less than 40 GB free on the volume of /Users/x/work"),
        ("disk.full", .diskFull, "OSError: [Errno 28] No space left on device"),
        ("icloud.detritus", .cloudFolder, "x.app: resource fork, Finder information, or similar detritus not allowed"),
    ]

    private func classify(_ log: String, sources: [String] = [], keys: String = "",
                          mounted: Bool = true, readable: Bool = true) -> PortingFailureReason {
        PortingFailureClassifier.classify(log: log, keysPath: keys, sourcePaths: sources,
                                          isReadable: { _ in readable }, isMounted: { _ in mounted })
    }

    func testEveryRowMatchesItsEngineLine() {
        for row in Self.engineLines {
            XCTAssertEqual(classify("step 1\n\(row.line)\nexit 1").kind, row.kind, row.id)
        }
    }

    func testEveryTableRowHasAnEngineLine() {
        XCTAssertEqual(Set(PortingFailureClassifier.table.map(\.id)), Set(Self.engineLines.map(\.id)))
    }

    func testRealStopWinsOverProvisionalWarning() {
        let log = """
        [RED] provisional game profile: values guessed from the survey, the game may not boot
        stage 3 of 7
        [RED] 3 files fail the NCA's hash check (an incomplete copy or a broken download)
        """
        XCTAssertEqual(classify(log).kind, .damagedNSP)
    }

    func testProvisionalAloneIsNoProfile() {
        XCTAssertEqual(classify("[RED] provisional game profile: values guessed\nTraceback").kind, .noProfile)
    }

    func testNoProfileDetailIsJumpTable() {
        let log = """
        {"ev": "say", "msg": "no game profile for 0100D1B006744000: reusing the provisional profile"}
        {"ev": "say", "msg": "[RED] patch_nso.py exit code 1 on main (full output: rewrite_main.log)"}
        {"ev": "say", "msg": "AssertionError: jump table 997b78"}
        """
        let reason = classify(log)
        XCTAssertEqual(reason, PortingFailureReason(kind: .noProfile, detail: "997b78"))
        XCTAssertTrue(reason.what(game: "A Game").contains("0x997b78"))
    }

    func testJSONWrappedLinesMatch() {
        XCTAssertEqual(classify(#"{"ev": "say", "msg": "[RED] no such file: /Users/x/keys/prod.keys"}"#).kind, .keys)
    }

    func testPortedGameDecodesWithoutReason() throws {
        let game = PortedGame(name: "A", url: URL(fileURLWithPath: "/a.app"), platform: .macApp, sizeBytes: 1,
                              modificationDate: Date(timeIntervalSince1970: 0))
        var data = try JSONEncoder().encode(game)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "portingFailureReason")
        data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try JSONDecoder().decode(PortedGame.self, from: data).portingFailureReason)

        var failed = game
        failed.portingFailureReason = PortingFailureReason(kind: .diskFull, detail: "40")
        let back = try JSONDecoder().decode(PortedGame.self, from: JSONEncoder().encode(failed))
        XCTAssertEqual(back.portingFailureReason, PortingFailureReason(kind: .diskFull, detail: "40"))
    }

    func testUnmountedVolumeWinsFirst() {
        let reason = classify("[RED] no such file: /Volumes/Games/x.nsp", sources: ["/Volumes/Games/x.nsp"], mounted: false)
        XCTAssertEqual(reason, PortingFailureReason(kind: .driveMissing, detail: "Games"))
    }

    func testUnreadableKeysWithoutAMessage() {
        XCTAssertEqual(classify("nx_extract exit code 3", keys: "/k/prod.keys", readable: false).kind, .keys)
    }

    func testUnknownKeepsNoDetail() {
        XCTAssertEqual(classify("something odd"), PortingFailureReason(kind: .unknown, detail: nil))
    }

    func testDiskFullDetailIsGB() {
        XCTAssertEqual(classify("[RED] less than 40 GB free on the volume of /x").detail, "40")
    }

    func testNoTitleIDDetailIsFolder() {
        XCTAssertEqual(classify("[RED] no game package with a readable content meta in /Users/x/Foo").detail, "/Users/x/Foo")
        // Engines before nxnative 5c4dc18f said it this way.
        XCTAssertEqual(classify("[RED] no NSP with a readable title ID in /Users/x/Foo").detail, "/Users/x/Foo")
    }

    func testPortAnywayOnlyForTwoKinds() {
        XCTAssertEqual(PortingFailureReason(kind: .shaderRegression).action, .portAnyway(flag: "--allow-shader-regressions"))
        XCTAssertEqual(PortingFailureReason(kind: .damagedNSP).action, .portAnyway(flag: "--allow-damaged"))
        XCTAssertEqual(PortingFailureReason(kind: .otherMetal).action, .openEngineSettings)
        for kind in PortingFailureReason.Kind.allCases where kind != .shaderRegression && kind != .damagedNSP {
            if case .portAnyway = PortingFailureReason(kind: kind).action { XCTFail("\(kind) offers Port anyway") }
        }
    }

    func testArgumentsKeepGateFlag() {
        XCTAssertEqual(PortingFailureClassifier.arguments(["a", "--allow-other-metal", "--allow-damaged"],
                                                          adding: "--allow-shader-regressions"),
                       ["a", "--allow-other-metal", "--allow-shader-regressions"])
        XCTAssertEqual(PortingFailureClassifier.arguments(["a", "--allow-damaged"], adding: nil), ["a"])
    }

    func testKeyOutcomeMapping() {
        let tooOld = PortingFailureReason.from(.tooOld(part: .update, generation: 12, missing: "key_area_key_application_0b"))
        XCTAssertEqual(tooOld, PortingFailureReason(kind: .keysTooOld, detail: "12.1.0"))
        XCTAssertEqual(PortingFailureReason.from(.wrongHeaderKey(file: "base.nsp")),
                       PortingFailureReason(kind: .keysWrong, detail: "base.nsp"))
        XCTAssertEqual(PortingFailureReason.from(.noHeaderKey)?.kind, .keys)
        XCTAssertNil(PortingFailureReason.from(.fits))
        XCTAssertNil(PortingFailureReason.from(.cannotCheck(file: "x.xci")))
    }

    func testEveryKindHasCopy() {
        for kind in PortingFailureReason.Kind.allCases {
            let reason = PortingFailureReason(kind: kind, detail: "detail")
            XCTAssertFalse(reason.title.isEmpty, "\(kind)")
            XCTAssertFalse(reason.title.hasSuffix("."), "\(kind) title ends with a full stop")
            XCTAssertFalse(reason.what(game: "Game").isEmpty, "\(kind)")
            XCTAssertFalse(reason.next.isEmpty, "\(kind)")
        }
    }

    func testTooOldCopyNamesFirmware() {
        XCTAssertTrue(PortingFailureReason(kind: .keysTooOld, detail: "19.0.0").next.contains("19.0.0"))
    }

    func testEngineKeyErrorNamesFirmwareWithoutKeepingKeyNames() {
        let line = Self.engineLines.first { $0.id == "keys.tooOld" }!.line
        let reason = classify(#"{"ev":"say","msg":""# + line + #""}"#)
        XCTAssertEqual(reason, PortingFailureReason(kind: .keysTooOld, detail: "21.0.0"))
        XCTAssertEqual(reason.action, .importKeys)
        XCTAssertFalse(reason.next.contains("key_area_key"))
    }

    func testUnknownFirmwareDoesNotRecommendTheLastKnownVersion() {
        let log = "prod.keys has no titlekek_15 (master key 15, which came with a firmware after 21.0.0): the keys are older than the game; dump prod.keys again from a console on a firmware after 21.0.0"
        XCTAssertEqual(classify(log), PortingFailureReason(kind: .keysTooOld))
    }

    func testFinalKeyPreflightWinsOverEarlierPackageProbeFirmware() {
        let earlier = #"{"ev":"say","msg":"[RED] base.nsp: prod.keys has no key_area_key_application_10 (master key 10, which came with firmware 17.0.0): the keys are older than the game"}"#
        let final = #"{"ev":"say","msg":"[RED] update.nsp: prod.keys has no key_area_key_application_14 (master key 14, which came with firmware 21.0.0): the keys are older than the game"}"#
        XCTAssertEqual(classify(earlier + "\n" + final).detail, "21.0.0")
        let future = final.replacingOccurrences(of: "which came with firmware 21.0.0", with: "which came with a firmware after 21.0.0")
        XCTAssertNil(classify(earlier + "\n" + future).detail)
    }

    func testMissingLanguageNamesItAndPointsToGameOptions() {
        let line = Self.engineLines.first { $0.id == "language.missing" }!.line
        let reason = classify(#"{"ev":"say","msg":""# + line + #""}"#)
        XCTAssertEqual(reason.kind, .unknown, "an older launcher still reads the saved kind")
        XCTAssertEqual(reason.title, "The game does not have this language")
        XCTAssertTrue(reason.what(game: "Game").contains("Japanese"))
        XCTAssertTrue(reason.next.contains("Game Default"))
        XCTAssertEqual(reason.action, .none)
        XCTAssertEqual(PortingFailureReason(kind: .unknown).title, "The porting stopped")
    }

    func testDamageThatAllowDamagedCannotReadOffersNoPortAnyway() {
        for id in ["nsp.tables", "nsp.truncated"] {
            let reason = classify(Self.engineLines.first { $0.id == id }!.line)
            XCTAssertEqual(reason.kind, .damagedNSP, id)
            XCTAssertEqual(reason.action, .none, id)
            XCTAssertFalse(reason.next.contains("port anyway"), id)
        }
        let files = classify(Self.engineLines.first { $0.id == "nsp.damaged" }!.line)
        XCTAssertEqual(files.action, .portAnyway(flag: "--allow-damaged"))
    }

    func testMissingTicketDoesNotSuggestReplacingKeysOrPortAnyway() {
        let line = "[RED] Example.nsp: no title key for rights ID 00000000000000000000000000000000: the package has no common ticket for it"
        let reason = classify(line, keys: "/synthetic/prod.keys")
        XCTAssertEqual(reason.title, "Game ticket missing")
        XCTAssertEqual(reason.action, .none)
        XCTAssertTrue(reason.next.contains("ticket"))
    }

    func testMissingTicketKeepsThePersistedKindReadableByEarlierLaunchers() throws {
        let line = Self.engineLines.first { $0.id == "keys.ticket" }!.line
        let reason = classify(line)
        let data = try JSONEncoder().encode(reason)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "keys")
        let decoded = try JSONDecoder().decode(PortingFailureReason.self, from: data)
        XCTAssertEqual(decoded.title, "Game ticket missing")
        XCTAssertEqual(decoded.action, .none)
    }
}

/// The pinned engine still prints every message the table and the porting progress read; a re-pin that rewords one
/// fails here.
final class PortingFailureEngineTests: XCTestCase {
    func testFragmentsStillInPinnedEngine() throws {
        let explicitEngine = ProcessInfo.processInfo.environment["NX_TEST_ENGINE_REPO"]
        let engine = explicitEngine.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("nxnative")
        guard FileManager.default.fileExists(atPath: engine.appendingPathComponent(".git").path) else {
            if explicitEngine != nil { return XCTFail("NX_TEST_ENGINE_REPO is not an engine checkout") }
            throw XCTSkip("no ~/nxnative checkout")
        }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NXLibrary/ViewModels/AppViewModel.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        guard let match = text.range(of: #"pinnedEngineCommit = "[0-9a-f]{40}""#, options: .regularExpression) else {
            return XCTFail("no pinnedEngineCommit in AppViewModel.swift")
        }
        let pin = ProcessInfo.processInfo.environment["NX_TEST_ENGINE_COMMIT"]
            ?? String(text[match].dropFirst("pinnedEngineCommit = \"".count).dropLast())
        guard pin.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil else {
            return XCTFail("NX_TEST_ENGINE_COMMIT must be a full commit hash")
        }
        for row in PortingFailureClassifier.table where row.engineFragment != nil {
            let fragment = row.engineFragment!
            let found = gitGrep(fragment, at: pin, in: engine)
            if row.id == "zbic.missing" && !found { continue }
            XCTAssertTrue(found, "\(row.id): \"\(fragment)\" is no longer in nxnative \(pin.prefix(7))")
        }
        XCTAssertTrue(gitGrep(PortingProgress.shaderCacheWorkMessage, at: pin, in: engine),
                      "progress: \"\(PortingProgress.shaderCacheWorkMessage)\" is no longer in nxnative \(pin.prefix(7))")
    }

    private func gitGrep(_ fragment: String, at commit: String, in repo: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo.path, "grep", "-q", "-F", fragment, commit, "--", "scripts", "dm/gfx/tools", "dm/tools"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
