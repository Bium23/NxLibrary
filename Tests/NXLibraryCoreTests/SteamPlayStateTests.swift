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
}
