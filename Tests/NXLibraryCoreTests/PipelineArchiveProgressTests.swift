import XCTest
import Foundation
@testable import NXLibraryCore

final class PipelineArchiveProgressTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PipelineArchiveProgressTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testCountOccurrences() {
        let text = "hello \"vertex_function_descriptor\" world \"vertex_function_descriptor\" end"
        let data = Data(text.utf8)
        XCTAssertEqual(PipelineArchiveProgress.countOccurrences(of: "\"vertex_function_descriptor\"", in: data), 2)
        XCTAssertEqual(PipelineArchiveProgress.countOccurrences(of: "\"compute_function_descriptor\"", in: data), 0)
        XCTAssertEqual(PipelineArchiveProgress.countOccurrences(of: "", in: data), 0)
        XCTAssertEqual(PipelineArchiveProgress.countOccurrences(of: "test", in: Data()), 0)
    }

    func testCountDescriptors() {
        let json = """
        {
          "pipeline_descriptors": {
            "render_pipeline_descriptors": [
              { "vertex_function_descriptor": "fnd:1" },
              { "vertex_function_descriptor": "fnd:2" },
              { "vertex_function_descriptor": "fnd:3" }
            ],
            "compute_pipeline_descriptors": [
              { "compute_function_descriptor": "fnd:c1" }
            ]
          }
        }
        """
        let counts = PipelineArchiveProgress.countDescriptors(in: Data(json.utf8))
        XCTAssertEqual(counts.bases, 3)
        XCTAssertEqual(counts.computes, 1)
        XCTAssertEqual(counts.total, 4)
    }

    func testPollReturnsNilWhenNoBasesJson() {
        let scanner = PipelineArchiveProgress()
        let event = scanner.poll(psoWorkDirectory: tempDir, stageStartedAt: Date())
        XCTAssertNil(event)
    }

    func testPollTracksBatchesAndComputesETA() throws {
        let scanner = PipelineArchiveProgress()

        // 2,500 bases and 32 computes = 3 base batches (1000, 1000, 500) + 2 compute batches (16, 16)
        var descriptors: [String] = []
        for _ in 0..<2500 {
            descriptors.append("\"vertex_function_descriptor\"")
        }
        for _ in 0..<32 {
            descriptors.append("\"compute_function_descriptor\"")
        }
        let json = "{ " + descriptors.joined(separator: ", ") + " }"
        let scriptURL = tempDir.appendingPathComponent("bases.mtl4-json")
        try json.write(to: scriptURL, atomically: true, encoding: .utf8)

        let stageStartedAt = Date().addingTimeInterval(-60) // 60s ago

        // Initially no batches folder: active single batch check
        let initialEvent = scanner.poll(psoWorkDirectory: tempDir, stageStartedAt: stageStartedAt, now: Date())
        if case .progress(let fraction, let done, let total, let unit, let eta, _) = initialEvent {
            XCTAssertEqual(fraction, 0)
            XCTAssertEqual(done, 0)
            XCTAssertEqual(total, 2532)
            XCTAssertEqual(unit, "pipelines")
            XCTAssertNil(eta)
        } else {
            XCTFail("Expected progress event, got \(String(describing: initialEvent))")
        }

        // Create batches folder
        let batchesDir = tempDir.appendingPathComponent("batches.applegpu_test")
        try FileManager.default.createDirectory(at: batchesDir, withIntermediateDirectories: true)

        // Batch 1 (00001) completed
        let b1 = batchesDir.appendingPathComponent("00001")
        try FileManager.default.createDirectory(at: b1, withIntermediateDirectories: true)
        try "key1".write(to: b1.appendingPathComponent("key.applegpu_test"), atomically: true, encoding: .utf8)

        // Batch 2 (00002) in progress with 500 translate- files
        let b2 = batchesDir.appendingPathComponent("00002")
        try FileManager.default.createDirectory(at: b2, withIntermediateDirectories: true)
        for i in 0..<500 {
            try "".write(to: b2.appendingPathComponent("translate-\(i)"), atomically: true, encoding: .utf8)
        }

        let now = stageStartedAt.addingTimeInterval(30) // 30s elapsed
        let activeEvent = scanner.poll(psoWorkDirectory: tempDir, stageStartedAt: stageStartedAt, now: now)

        if case .progress(let fraction, let done, let total, let unit, let eta, _) = activeEvent {
            XCTAssertEqual(done, 1500) // 1000 from b1 + 500 from b2
            XCTAssertEqual(total, 2532)
            XCTAssertEqual(unit, "pipelines")
            XCTAssertEqual(fraction, 1500.0 / 2532.0, accuracy: 1e-6)
            // Rate = 1500 / 30 = 50 pipelines/s. Remaining = 1032. ETA = 1032 / 50 = 20.64s
            XCTAssertNotNil(eta)
            XCTAssertEqual(eta!, 20.64, accuracy: 1.0)
        } else {
            XCTFail("Expected progress event, got \(String(describing: activeEvent))")
        }
    }

    func testPollPreservesMonotonicDone() throws {
        let scanner = PipelineArchiveProgress()

        var descriptors: [String] = []
        for _ in 0..<1000 {
            descriptors.append("\"vertex_function_descriptor\"")
        }
        let json = "{ " + descriptors.joined(separator: ", ") + " }"
        let scriptURL = tempDir.appendingPathComponent("bases.mtl4-json")
        try json.write(to: scriptURL, atomically: true, encoding: .utf8)

        let batchesDir = tempDir.appendingPathComponent("batches.applegpu_test")
        let b1 = batchesDir.appendingPathComponent("00001")
        try FileManager.default.createDirectory(at: b1, withIntermediateDirectories: true)

        // 400 translate files
        for i in 0..<400 {
            try "".write(to: b1.appendingPathComponent("translate-\(i)"), atomically: true, encoding: .utf8)
        }
        let event1 = scanner.poll(psoWorkDirectory: tempDir, stageStartedAt: Date(), now: Date())
        if case .progress(_, let done, _, _, _, _) = event1 {
            XCTAssertEqual(done, 400)
        }

        // Simulate metal-tt cleaning up temporaries before key file is written
        for i in 0..<400 {
            try? FileManager.default.removeItem(at: b1.appendingPathComponent("translate-\(i)"))
        }

        let event2 = scanner.poll(psoWorkDirectory: tempDir, stageStartedAt: Date(), now: Date())
        if case .progress(_, let done, _, _, _, _) = event2 {
            XCTAssertEqual(done, 400, "Done count must not drop during temporary cleanup")
        }
    }
}
