import XCTest
@testable import NXLibraryCore

final class SteamPlayStateTests: XCTestCase {
    private let app = CatalogNativeApplication(NativeMacApplication(
        url: URL(fileURLWithPath: "/Steam/steamapps/common/Game/Game.app"),
        executableURL: URL(fileURLWithPath: "/Steam/steamapps/common/Game/Game.app/Contents/MacOS/Game"),
        bundleIdentifier: "com.example.game", name: "Game", architectures: [.arm64], isDeclaredGame: true, fileObservations: []))
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private var game: NativeProcessObservation {
        .init(pid: 42, bundleURL: app.url, executableURL: app.executableURL)
    }
    private let steamClient = NativeProcessObservation(pid: 7, bundleURL: URL(fileURLWithPath: "/Applications/Steam.app"),
                                                       executableURL: URL(fileURLWithPath: "/Applications/Steam.app/Contents/MacOS/steam_osx"))

    func testAnInstallationReachedThroughASymlinkMatchesTheRunningApp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("Drive/common/Game")
        try FileManager.default.createDirectory(at: real.appendingPathComponent("Game.app/Contents/MacOS"), withIntermediateDirectories: true)
        try Data().write(to: real.appendingPathComponent("Game.app/Contents/MacOS/Game"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("steamapps"), withDestinationURL: root.appendingPathComponent("Drive"))
        let linked = root.appendingPathComponent("steamapps/common/Game/Game.app")
        let installed = CatalogNativeApplication(NativeMacApplication(
            url: linked, executableURL: linked.appendingPathComponent("Contents/MacOS/Game"),
            bundleIdentifier: "com.example.game", name: "Game", architectures: [.arm64], isDeclaredGame: true, fileObservations: []))
        // The system names the real path; the caller hands it over in canonical form.
        let running = NativeProcessObservation(pid: 42, bundleURL: real.appendingPathComponent("Game.app"),
                                               executableURL: real.appendingPathComponent("Game.app/Contents/MacOS/Game")).canonical()
        var state = SteamPlayState()
        XCTAssertEqual(state.observe([running], application: installed, now: t0), .started(pid: 42))
        XCTAssertNil(state.observe([running], application: installed, now: t0.addingTimeInterval(30)), "still the same game")
    }

    func testHandOffStartsNoSessionUntilTheGameItselfRuns() {
        var state = SteamPlayState()
        XCTAssertEqual(state.requestPlay(target: .steam(appID: 570), clientAvailable: true, now: t0),
                       .handOff(URL(string: "steam://run/570")!, generation: 1))
        state.handoffFinished(accepted: true, generation: 1)
        XCTAssertNil(state.observe([steamClient], application: app, now: t0.addingTimeInterval(5)), "Steam alone is not the game")
        XCTAssertEqual(state.phase, .starting(since: t0, accepted: true))
        XCTAssertEqual(state.observe([steamClient, game], application: app, now: t0.addingTimeInterval(20)), .started(pid: 42))
        XCTAssertEqual(state.requestPlay(target: .steam(appID: 570), clientAvailable: true, now: t0), .resume(pid: 42))
        // The game quits while Steam stays open: the session ends.
        XCTAssertEqual(state.observe([steamClient], application: app, now: t0.addingTimeInterval(600)), .ended(pid: 42))
        XCTAssertEqual(state.phase, .idle)
    }

    func testDuplicatePlayAndLateAnswersChangeNothing() {
        var state = SteamPlayState()
        _ = state.requestPlay(target: .steam(appID: 570), clientAvailable: true, now: t0)
        XCTAssertEqual(state.requestPlay(target: .steam(appID: 570), clientAvailable: true, now: t0), .wait)
        state.cancel()
        _ = state.requestPlay(target: .steam(appID: 570), clientAvailable: true, now: t0)
        state.handoffFinished(accepted: false, generation: 1)   // the cancelled request's answer
        XCTAssertEqual(state.phase, .starting(since: t0, accepted: false))
        state.handoffFinished(accepted: false, generation: state.generation)
        XCTAssertEqual(state.phase, .failed(.handoffRejected))
    }

    func testRefusalsAndTimeoutNeverStartASession() {
        var state = SteamPlayState()
        XCTAssertEqual(state.requestPlay(target: nil, clientAvailable: true, now: t0), .refuse(.unavailable))
        XCTAssertEqual(state.requestPlay(target: .nxnative(appURL: app.url), clientAvailable: true, now: t0), .refuse(.unavailable))
        XCTAssertEqual(state.requestPlay(target: .steam(appID: 0), clientAvailable: true, now: t0), .refuse(.unavailable))
        XCTAssertEqual(state.requestPlay(target: .steam(appID: 570), clientAvailable: false, now: t0), .refuse(.clientMissing))
        _ = state.requestPlay(target: .steam(appID: 570), clientAvailable: true, now: t0)
        XCTAssertNil(state.observe([], application: app, now: t0.addingTimeInterval(SteamPlayState.startDeadline + 1)))
        XCTAssertEqual(state.phase, .failed(.notStarted))
        // A game that appears later (an update finished) is still followed.
        XCTAssertEqual(state.observe([game], application: app, now: t0.addingTimeInterval(900)), .started(pid: 42))
    }

    func testOnlyThisInstallationsAppMatches() {
        XCTAssertTrue(SteamPlayState.matches(game, app))
        XCTAssertTrue(SteamPlayState.matches(.init(pid: 1, bundleURL: app.url, executableURL: nil), app))
        XCTAssertFalse(SteamPlayState.matches(steamClient, app))
        let otherCopy = NativeProcessObservation(pid: 3, bundleURL: URL(fileURLWithPath: "/Volumes/Ext/Game.app"),
                                                 executableURL: URL(fileURLWithPath: "/Volumes/Ext/Game.app/Contents/MacOS/Game"))
        XCTAssertFalse(SteamPlayState.matches(otherCopy, app), "same bundle ID elsewhere is another installation")
        let helper = NativeProcessObservation(pid: 4, bundleURL: app.url,
                                              executableURL: app.url.appendingPathComponent("Contents/MacOS/CrashReporter"))
        XCTAssertFalse(SteamPlayState.matches(helper, app))
        XCTAssertNil(SteamPlayState.launchURL(appID: 0))
    }

    func testAGameAlreadyRunningIsFollowedWithoutAPlay() {
        var state = SteamPlayState()
        XCTAssertEqual(state.observe([game], application: app, now: t0), .started(pid: 42))
        // The same pid reused by another program is not mistaken for the game.
        XCTAssertEqual(state.observe([.init(pid: 42, bundleURL: steamClient.bundleURL, executableURL: steamClient.executableURL)],
                                     application: app, now: t0), .ended(pid: 42))
        XCTAssertNil(state.observe([.init(pid: 42, bundleURL: steamClient.bundleURL, executableURL: steamClient.executableURL)],
                                   application: app, now: t0))
    }

    func testARunningSessionFollowsTheProcessItSawStartNotTheInstallationNow() {
        var state = SteamPlayState()
        XCTAssertEqual(state.observe([game], application: app, now: t0), .started(pid: 42))
        // The installation disappears from the catalog (a refresh): the game keeps playing.
        XCTAssertNil(state.observe([game], application: nil, now: t0.addingTimeInterval(60)))
        // The catalog now names the app at a new path: one session, not ended and started again.
        let moved = CatalogNativeApplication(NativeMacApplication(
            url: URL(fileURLWithPath: "/Volumes/Games/Game.app"),
            executableURL: URL(fileURLWithPath: "/Volumes/Games/Game.app/Contents/MacOS/Game"),
            bundleIdentifier: "com.example.game", name: "Game", architectures: [.arm64], isDeclaredGame: true, fileObservations: []))
        XCTAssertNil(state.observe([game], application: moved, now: t0.addingTimeInterval(120)))
        XCTAssertEqual(state.phase, .running(pid: 42))
        // With no installation to compare, the pid reused by another program still ends it.
        XCTAssertEqual(state.observe([steamClient, .init(pid: 42, bundleURL: steamClient.bundleURL, executableURL: nil)],
                                     application: nil, now: t0.addingTimeInterval(180)), .ended(pid: 42))
    }
}

final class SteamBackgroundLaunchTests: XCTestCase {
    func testSilentArgumentsOnlyWhenPlayStartsSteamAndTheSettingIsOn() {
        XCTAssertEqual(SteamBackgroundLaunch.arguments(enabled: true, steamRunning: false), ["-silent", "-nofriendsui"])
        XCTAssertEqual(SteamBackgroundLaunch.arguments(enabled: true, steamRunning: true), [])
        XCTAssertEqual(SteamBackgroundLaunch.arguments(enabled: false, steamRunning: false), [])
    }

    func testSteamIsKeptAwayOnlyWhileWaitingThenComesBackIfTheGameIsLate() {
        let start = Date(timeIntervalSince1970: 1_000)
        let waiting = SteamPlayState.Phase.starting(since: start, accepted: true)
        XCTAssertTrue(SteamBackgroundLaunch.keepsSteamAway(enabled: true, phase: waiting, now: start.addingTimeInterval(5)))
        XCTAssertFalse(SteamBackgroundLaunch.keepsSteamAway(enabled: false, phase: waiting, now: start.addingTimeInterval(5)))
        let late = start.addingTimeInterval(SteamBackgroundLaunch.attentionDelay + 1)
        XCTAssertFalse(SteamBackgroundLaunch.keepsSteamAway(enabled: true, phase: waiting, now: late))
        XCTAssertTrue(SteamBackgroundLaunch.mayNeedPlayer(enabled: true, phase: waiting, now: late))
        XCTAssertFalse(SteamBackgroundLaunch.mayNeedPlayer(enabled: true, phase: waiting, now: start.addingTimeInterval(5)))
        XCTAssertFalse(SteamBackgroundLaunch.keepsSteamAway(enabled: true, phase: .running(pid: 7), now: start))
        XCTAssertFalse(SteamBackgroundLaunch.mayNeedPlayer(enabled: true, phase: .idle, now: late))
    }
}
