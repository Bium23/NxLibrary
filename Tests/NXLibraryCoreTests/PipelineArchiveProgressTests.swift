import XCTest
@testable import NXLibraryCore

final class PipelineArchiveProgressTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)
    private let arch = "applegpu_g17s"

    private func poll(_ text: String, age: TimeInterval = 30, stale: Bool = false) throws -> BuildEvent? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("pso_offline_mac.log")
        try text.write(to: log, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: start.addingTimeInterval(stale ? -60 : age)], ofItemAtPath: log.path)
        return PipelineArchiveProgress().poll(logURL: log, architectures: [arch], stageStartedAt: start, now: start.addingTimeInterval(age))
    }

    private var header: String {
        "pso_offline: \(arch): metal-tt, 2500 bases, 32 compute pipelines (minutes) ...\n"
    }

    func testCountsOnlyBatchesReportedReadyNotStartedOrTemporaryFiles() throws {
        let text = header + """
        pso_offline: applegpu_g17s: batch 1/5: 1000 bases, compiling or checking cache
        pso_offline: applegpu_g17s: batch 1/5: ready (compiled)
        pso_offline: applegpu_g17s: batch 2/5: 1000 bases, compiling or checking cache
        """ + "\n"
        let event = try poll(text)
        guard case .progress(let fraction, let done, let total, let unit, let eta, _) = event else { return XCTFail("Missing progress") }
        XCTAssertEqual(done, 1000)
        XCTAssertEqual(total, 2532)
        XCTAssertEqual(unit, "pipelines")
        XCTAssertEqual(fraction, 1000.0 / 2532, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(eta), 45.96, accuracy: 0.01)
    }

    func testReusedBatchesCountButSupplyNoCompilationRate() throws {
        let event = try poll(header + """
        pso_offline: applegpu_g17s: batch 1/5: 1000 bases, compiling or checking cache
        pso_offline: applegpu_g17s: batch 1/5: ready (reused)
        """ + "\n")
        guard case .progress(_, let done, _, _, let eta, _) = event else { return XCTFail("Missing progress") }
        XCTAssertEqual(done, 1000)
        XCTAssertNil(eta)
    }

    func testStaleLogDoesNotReportLastBuildsProgress() throws {
        XCTAssertNil(try poll(header, stale: true))
    }

    func testTruncatedUnknownAndPartialLinesDoNotInventCounts() throws {
        XCTAssertNil(try poll("a different engine's log\n"))
        let event = try poll(header + "pso_offline: applegpu_g17s: batch 1/5: 1000 bases, compiling or checking cache\n" + "pso_offline: applegpu_g17s: batch 1/5: ready (compiled)")
        guard case .progress(_, let done, _, _, _, _) = event else { return XCTFail("Missing progress") }
        XCTAssertEqual(done, 0, "The writer has not finished this line yet")
    }

    func testParallelComputeBatchesAndCustomBatchSizesUseActualCounts() throws {
        let event = try poll(header + """
        pso_offline: applegpu_g17s: batch 1/3: 2500 bases, compiling or checking cache
        pso_offline: applegpu_g17s: batch 1/3: ready (compiled)
        pso_offline: applegpu_g17s: batch 2/3: 16 compute pipelines, compiling or checking cache
        pso_offline: applegpu_g17s: batch 3/3: 16 compute pipelines, compiling or checking cache
        pso_offline: applegpu_g17s: batch 3/3: ready (compiled)
        pso_offline: applegpu_g17s: batch 3/3: ready (compiled)
        """ + "\n")
        guard case .progress(_, let done, _, _, _, _) = event else { return XCTFail("Missing progress") }
        XCTAssertEqual(done, 2516, "Duplicate ready lines must not double count")
    }

    func testParallelCompilerMessagesSharingALineDoNotLoseABatch() throws {
        let event = try poll(header + """
        pso_offline: applegpu_g17s: batch 4/5: 16 compute pipelines, compiling or checking cachepso_offline: applegpu_g17s: batch 5/5: 16 compute pipelines, compiling or checking cache
        pso_offline: applegpu_g17s: batch 4/5: ready (compiled)
        pso_offline: applegpu_g17s: batch 5/5: ready (compiled)
        """ + "\n")
        guard case .progress(_, let done, _, _, _, _) = event else { return XCTFail("Missing progress") }
        XCTAssertEqual(done, 32)
    }

    func testOtherArchitecturesDoNotCountTowardThisMac() throws {
        let event = try poll(header + """
        pso_offline: applegpu_g18p: batch 1/1: 2532 bases, compiling or checking cache
        pso_offline: applegpu_g18p: batch 1/1: ready (compiled)
        """ + "\n")
        guard case .progress(_, let done, _, _, _, _) = event else { return XCTFail("Missing progress") }
        XCTAssertEqual(done, 0)
    }
}
