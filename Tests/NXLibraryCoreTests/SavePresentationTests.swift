import XCTest
@testable import NXLibraryCore

final class SavePresentationTests: XCTestCase {
    func testSavesOpensPanelWithoutMovingCheats() {
        XCTAssertEqual(GameOptionsRow.openSaves.title, "Saves")
        XCTAssertTrue(GameOptionsRow.openSaves.opensSubmenu)
        let p = GameOptionsPresentation(supportsRenderScale: false, isPlayable: true, sourcesDetached: false)
        let rows = p.focusableRows(level: .main, origin: .details)
        XCTAssertEqual(Array(rows.prefix(3)), [.play, .editDetails, .cheats])
        XCTAssertEqual(Array(rows.suffix(4)), [.rebuild, .showInFinder, .openSaves, .removeGame])
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
