import XCTest
@testable import NXLibraryCore

final class SavePresentationTests: XCTestCase {
    func testSavesOpensPanelWithoutMovingCheats() {
        XCTAssertEqual(GameOptionsRow.openSaves.title, "Saves")
        XCTAssertTrue(GameOptionsRow.openSaves.opensSubmenu)
        let p = GameOptionsPresentation(supportsRenderScale: false, isPlayable: true, sourcesDetached: false)
        let rows = p.focusableRows(level: .main, origin: .details)
        XCTAssertEqual(Array(rows.prefix(4)), [.play, .editDetails, .cheats, .openSaves])
        XCTAssertEqual(Array(rows.suffix(3)), [.rebuild, .showInFinder, .removeGame])
    }
    func testCloudImportHasAnActionInsteadOfBeingDisabled() {
        XCTAssertEqual(SavePresentation.importAction(available: true, busy: false, running: false,
            recovery: false, cloud: true), .cloudSettings)
        XCTAssertEqual(SavePresentation.importAction(available: true, busy: false, running: false,
            recovery: false, cloud: false), .chooseFolder)
        XCTAssertEqual(SavePresentation.importAction(available: true, busy: true, running: false,
            recovery: false, cloud: true), .unavailable)
        XCTAssertEqual(SavePresentation.importAction(available: true, busy: false, running: true,
            recovery: false, cloud: false), .unavailable)
    }
    func testRestoreWarningNamesVersionsAndKeepsBackupPromise() {
        let identity = SaveIdentity(titleID: "0100000000000001", gameName: "Game", version: "1.0", buildID: nil)
        let snapshot = SaveSnapshot(id: UUID(), identity: identity, created: Date(), reason: .manual, presentSlots: [], entries: [])
        let message = SavePresentation.restoreMessage(snapshot, installedVersion: "2.0")
        XCTAssertTrue(message.contains("1.0")); XCTAssertTrue(message.contains("2.0"))
        XCTAssertTrue(message.contains("backed up")); XCTAssertTrue(message.contains("Cloud"))
    }
    func testRunningAndCloudCopyExplainsScope() {
        XCTAssertTrue(SavePresentation.cloudNotice.contains("local"))
        XCTAssertTrue(SavePresentation.closedNotice.contains("Finder"))
        XCTAssertTrue(SavePresentation.importWarning.contains("newer"))
    }
}
