import XCTest
@testable import NXLibraryCore

final class SaveOperationGateTests: XCTestCase {
    func testSharedTitleIsExclusiveAndOtherGamesRemainFree() throws {
        let gate = SaveOperationGate()
        let token = try XCTUnwrap(gate.begin(titleID: "01000000000000ab"))
        XCTAssertNil(gate.begin(titleID: "01000000000000AB"))
        XCTAssertNotNil(gate.begin(titleID: "0100000000000002"))
        gate.end(titleID: "01000000000000AB", token: UUID())
        XCTAssertTrue(gate.isBusy(titleID: "01000000000000ab"))
        gate.end(titleID: "01000000000000AB", token: token)
        XCTAssertFalse(gate.isBusy(titleID: "01000000000000ab"))
    }
    func testRecoveryBlockSurvivesLeaseAndCanBeRecoveredUnderLease() throws {
        let gate = SaveOperationGate()
        gate.setRecoveryBlocked(true, titleID: "0100000000000001")
        XCTAssertNil(gate.begin(titleID: "0100000000000001"))
        let token = try XCTUnwrap(gate.begin(titleID: "0100000000000001", recovering: true))
        gate.end(titleID: "0100000000000001", token: token)
        XCTAssertTrue(gate.isBusy(titleID: "0100000000000001"))
        gate.setRecoveryBlocked(false, titleID: "0100000000000001")
        XCTAssertNotNil(gate.begin(titleID: "0100000000000001"))
    }
}
