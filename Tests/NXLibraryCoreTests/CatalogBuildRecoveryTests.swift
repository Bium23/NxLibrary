import XCTest
@testable import NXLibraryCore

final class CatalogBuildRecoveryTests: XCTestCase {
    private func generation(_ name: String, basedOn original: PortedGame) -> PortedGame {
        var result = original
        var record = original.lastBuild!
        record.outputPath = "/tmp/" + name + ".app"
        result.pendingInstall = PendingInstall(tempApp: URL(fileURLWithPath: "/tmp/held/" + name + ".app"), finalApp: original.url,
                                               record: record, toolchain: original.toolchain)
        result.lastBuild = record
        return result
    }

    func testRetainedNewerBuildSuspendsAutomaticInstallAndExplicitRetryUsesIt() throws {
        let a = generation("A", basedOn: CatalogTestSupport.completeLegacyGame())
        let b = generation("B", basedOn: a)
        var recoveries = CatalogBuildRecoveries()
        recoveries.retain(b)
        XCTAssertNil(try recoveries.pendingCandidate(persisted: a, explicitRetry: false))
        var latest = a; latest.isFavorite = false; latest.settings.language = "de"
        let candidate = try XCTUnwrap(recoveries.pendingCandidate(persisted: latest, explicitRetry: true))
        XCTAssertEqual(candidate.pendingInstall?.tempApp.path, "/tmp/held/B.app")
        XCTAssertEqual(candidate.lastBuild, b.lastBuild)
        XCTAssertFalse(candidate.isFavorite)
        XCTAssertEqual(candidate.settings.language, "de")
    }

    func testCommittingOldGenerationCannotDiscardNewerRecovery() throws {
        let a = generation("A", basedOn: CatalogTestSupport.completeLegacyGame())
        let b = generation("B", basedOn: a)
        var recoveries = CatalogBuildRecoveries()
        recoveries.retain(a); recoveries.retain(b)
        recoveries.acknowledge(id: a.id, matching: a)
        XCTAssertEqual(recoveries[a.id], b)
        recoveries.acknowledge(id: a.id, matching: nil)
        XCTAssertEqual(recoveries[a.id], b)
        recoveries.acknowledge(id: a.id, matching: b)
        XCTAssertNil(recoveries[a.id])
    }

    func testRetainedInstalledResultDoesNotResurrectOlderPendingInstallation() throws {
        let a = generation("A", basedOn: CatalogTestSupport.completeLegacyGame())
        var b = generation("B", basedOn: a); b.pendingInstall = nil; b.status = .built
        var recoveries = CatalogBuildRecoveries(); recoveries.retain(b)
        let candidate = try XCTUnwrap(recoveries.pendingCandidate(persisted: a, explicitRetry: true))
        XCTAssertNil(candidate.pendingInstall)
        XCTAssertEqual(candidate.lastBuild, b.lastBuild)
        XCTAssertNil(try recoveries.pendingCandidate(persisted: a, explicitRetry: false))
    }
}
