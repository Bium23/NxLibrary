import XCTest
@testable import NXLibraryCore

final class FirstRunSetupTests: XCTestCase {
    func testSourceReviewWaitsForASingleReadyTitleAndConsumesEachArrivalOnce() {
        var entry = FirstRunSetup.ReviewEntry()
        let id = UUID()
        XCTAssertFalse(entry.consume(id, isReady: false, titleCount: 0))
        XCTAssertFalse(entry.consume(id, isReady: true, titleCount: 2))
        XCTAssertTrue(entry.consume(id, isReady: true, titleCount: 1))
        XCTAssertFalse(entry.consume(id, isReady: true, titleCount: 1))
        XCTAssertFalse(entry.consume(nil, isReady: true, titleCount: 1))
    }

    func testAnotherAcceptedSelectionCanReviewWithoutChangingRoute() {
        var entry = FirstRunSetup.ReviewEntry()
        let first = UUID(), second = UUID()
        XCTAssertTrue(entry.consume(first, isReady: true, titleCount: 1))
        XCTAssertTrue(entry.consume(second, isReady: true, titleCount: 1))
        XCTAssertFalse(entry.consume(second, isReady: true, titleCount: 1))
    }

    func testNewUserContinuesToGamesBeforeSetupIsCompleted() {
        var flow = FirstRunSetup(completed: false)
        XCTAssertEqual(flow.page, .requirements)
        flow.advance()
        XCTAssertEqual(flow.page, .games)
        XCTAssertFalse(flow.isCompleted)
        XCTAssertEqual(flow.pageToRemember, "games")
    }

    func testSkipIsRememberedEvenWhenNoGamesHaveBeenAdded() {
        var flow = FirstRunSetup(completed: false)
        flow.advance()
        flow.finish()
        XCTAssertTrue(flow.isCompleted)
        XCTAssertEqual(flow.page, .requirements)
        XCTAssertNil(flow.pageToRemember)
        let nextLaunch = FirstRunSetup(completed: flow.isCompleted, savedPage: "games")
        XCTAssertTrue(nextLaunch.isCompleted)
        flow.advance()
        XCTAssertTrue(flow.isCompleted, "A stale Continue action must not restart onboarding")
    }

    func testInterruptedSetupResumesOnTheGamesPage() {
        var flow = FirstRunSetup(completed: false)
        flow.advance()
        let resumed = FirstRunSetup(completed: false, savedPage: flow.pageToRemember)
        XCTAssertEqual(resumed.page, .games)
        XCTAssertFalse(resumed.isCompleted)
    }

    func testManualReopenVisitsBothPagesWithoutClearingCompletion() {
        var flow = FirstRunSetup(completed: true)
        flow.advance()
        XCTAssertEqual(flow.page, .games)
        XCTAssertTrue(flow.isCompleted)
        XCTAssertNil(flow.pageToRemember)
        flow.goBack()
        XCTAssertEqual(flow.page, .requirements)
        XCTAssertTrue(flow.isCompleted)
    }

    func testExistingUsersIgnoreStaleOrUnknownProgress() {
        XCTAssertTrue(FirstRunSetup(completed: true, savedPage: "games").isCompleted)
        XCTAssertEqual(FirstRunSetup(completed: false, savedPage: "unknown").page, .requirements)
    }

    func testBackReturnsToRequirementsWithoutCompletingSetup() {
        var flow = FirstRunSetup(completed: false, savedPage: "games")
        flow.goBack()
        XCTAssertEqual(flow.page, .requirements)
        XCTAssertFalse(flow.isCompleted)
    }

    func testLibraryIsNotReportedEmptyWhileDiscoveryIsRunning() {
        XCTAssertEqual(FirstRunSetup.libraryState(isScanning: true, gameCount: 0), .scanning)
        XCTAssertEqual(FirstRunSetup.libraryState(isScanning: true, gameCount: 3), .scanning)
        XCTAssertEqual(FirstRunSetup.libraryState(isScanning: false, gameCount: 0), .empty)
        XCTAssertEqual(FirstRunSetup.libraryState(isScanning: false, gameCount: 1), .ready)
    }

    func testKeyboardAndControllerNavigationReachSkipAndBack() {
        var focus = FirstRunSetup.Focus.apps
        focus = focus.moved(.down)
        XCTAssertEqual(focus, .file)
        focus = focus.moved(.down)
        XCTAssertEqual(focus, .folder)
        focus = focus.moved(.down)
        XCTAssertEqual(focus, .finish)
        XCTAssertEqual(focus.moved(.left), .back)
        XCTAssertEqual(FirstRunSetup.Focus.back.moved(.right), .finish)
        XCTAssertEqual(focus.moved(.up), .folder)
        XCTAssertEqual(FirstRunSetup.Focus.apps.moved(.up), .apps)
    }

    func testRequirementsScreenDoesNotContainTheGameFolders() {
        let all = SetupItemID.allCases.map {
            SetupItem(id: $0, title: $0.rawValue, state: .ready, chip: "", about: "", detail: "")
        }
        let requirements = SetupCheck.requirements(all)
        XCTAssertEqual(requirements.map(\.id), [.xcode, .metal, .dotnet, .engine, .runtime, .keys])
        XCTAssertEqual(SetupGrid.rowCounts(requirements.count, maxPerRow: 3), [3, 3])
    }

    func testUnavailableGameFolderDoesNotReopenTheTechnicalSetup() {
        let folder = SetupItem(id: .library, title: "Game apps", state: .warning, chip: "", about: "", detail: "")
        XCTAssertFalse(SetupCheck.shouldReopen(previous: [.library: .ready], current: [folder]))
    }
}
