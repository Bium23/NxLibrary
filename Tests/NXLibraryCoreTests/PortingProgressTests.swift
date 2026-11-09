import XCTest
@testable import NXLibraryCore

/// Event sequences shaped like LumenTale's porting log (the engine's `BuildEvent`s).
final class PortingProgressTests: XCTestCase {
    private func run(_ events: [BuildEvent]) -> PortingProgress {
        var progress = PortingProgress()
        events.forEach { progress.apply($0) }
        return progress
    }

    private let beforeShaders: [BuildEvent] = [
        .stage(k: 1, n: 1, name: "build ID lookup", step: nil),
        .stageEnd(name: "build ID lookup", ok: true, elapsed: 2.7, summary: nil),
        .stage(k: 1, n: 6, name: "build nx_extract", step: nil),
        .stage(k: 3, n: 7, name: "rewrite", step: "checking the inputs"),
        .stageEnd(name: "rewrite", ok: true, elapsed: 48, summary: nil),
    ]

    /// The shader stage up to its compiling step (the engine's own sub-steps first).
    private var shaders: [BuildEvent] {
        beforeShaders + [
            .stage(k: 5, n: 7, name: "Mac shaders", step: nil),
            .step("cache check"),
            .progress(fraction: 0.89, done: 24381, total: 27480, unit: "shaders", eta: 0.4),
            .step("translating"),
            .progress(fraction: 0.95, done: 26111, total: 27480, unit: "shaders", eta: 0.3),
            .step("compiling"),
        ]
    }

    /// Cache check and translating take seconds and restart their own fraction;
    /// only compiling is the percentage. Until then the tile tells what happens.
    func testOnlyCompilingCountsAsTheShaders() {
        var progress = run(Array(shaders.dropLast()))
        XCTAssertEqual(progress.phase, .preparing)
        XCTAssertEqual(progress.overall, 0)
        XCTAssertEqual(progress.stageName, "Mac shaders")
        XCTAssertEqual(progress.stepName, "translating")
        progress.apply(.step("compiling"))
        progress.apply(.progress(fraction: 0.0586, done: 1610, total: 27480, unit: "shaders", eta: 1080))
        XCTAssertEqual(progress.phase, .shaders)
        XCTAssertEqual(progress.overall, 0.9 * 0.0586, accuracy: 1e-9)
    }

    func testStageAndStepNamesFollowTheEngine() {
        let progress = run(beforeShaders + [.stage(k: 4, n: 7, name: "shader split", step: "checking the inputs")])
        XCTAssertEqual(progress.stageName, "shader split")
        XCTAssertEqual(progress.stepName, "checking the inputs")
    }

    func testStagesBeforeShadersShowStepAndCountOnly() {
        let progress = run(beforeShaders)
        XCTAssertEqual(progress.phase, .preparing)
        XCTAssertEqual(progress.step, 3)
        XCTAssertEqual(progress.count, 7)
        XCTAssertEqual(progress.overall, 0)
    }

    func testShaderFractionFillsNinetyPercent() {
        let progress = run(shaders + [.progress(fraction: 0.5, done: 13740, total: 27480, unit: "shaders", eta: 300)])
        XCTAssertEqual(progress.phase, .shaders)
        XCTAssertEqual(progress.overall, 0.45, accuracy: 1e-9)
        XCTAssertEqual(progress.shaderETA, 300)
    }

    func testNeverMovesBack() {
        let progress = run(shaders + [
            .progress(fraction: 0.6, done: nil, total: nil, unit: nil, eta: 100),
            .progress(fraction: 0.4, done: nil, total: nil, unit: nil, eta: 200),
        ])
        XCTAssertEqual(progress.overall, 0.54, accuracy: 1e-9)
    }

    func testFinishingStagesShareTheLastTenth() {
        var progress = run(shaders + [.stageEnd(name: "Mac shaders", ok: true, elapsed: 607, summary: nil)])
        XCTAssertEqual(progress.overall, 0.9, accuracy: 1e-9)
        progress.apply(.stage(k: 6, n: 7, name: "Mac host", step: "building"))
        XCTAssertEqual(progress.phase, .finishing)
        XCTAssertEqual(progress.overall, 0.9, accuracy: 1e-9, "a share is added when its stage ends")
        progress.apply(.stageEnd(name: "Mac host", ok: true, elapsed: 10, summary: nil))
        XCTAssertEqual(progress.overall, 0.9 + 0.1 / 3, accuracy: 1e-9)
        progress.apply(.stage(k: 7, n: 8, name: "Pipeline archive", step: nil))
        progress.apply(.stageEnd(name: "Pipeline archive", ok: true, elapsed: 79, summary: nil))
        XCTAssertEqual(progress.overall, 0.9 + 0.2 / 3, accuracy: 1e-9)
        progress.apply(.stage(k: 8, n: 8, name: "Mac app", step: nil))
        progress.apply(.stageEnd(name: "Mac app", ok: true, elapsed: 61, summary: nil))
        XCTAssertEqual(progress.overall, 1, accuracy: 1e-9)
        XCTAssertEqual(progress.finishingElapsed, 150, accuracy: 1e-9)
    }

    func testReusedShadersJumpToNinety() {
        let progress = run(shaders + [.stageEnd(name: "Mac shaders", ok: true, elapsed: 0.46, summary: "reused")])
        XCTAssertEqual(progress.overall, 0.9, accuracy: 1e-9)
    }

    func testNoShaderStageKeepsPreparingUntilDone() {
        var progress = run(beforeShaders + [
            .stage(k: 4, n: 5, name: "Mac host", step: nil),
            .stageEnd(name: "Mac host", ok: true, elapsed: 10, summary: nil),
        ])
        XCTAssertEqual(progress.phase, .preparing)
        XCTAssertEqual(progress.overall, 0)
        progress.finish(success: true)
        XCTAssertEqual(progress.phase, .done)
        XCTAssertEqual(progress.overall, 1)
    }

    func testFailedStageDoesNotAdvance() {
        var progress = run(shaders + [.stageEnd(name: "Mac shaders", ok: true, elapsed: 607, summary: nil),
                                      .stage(k: 6, n: 7, name: "Mac host", step: nil)])
        progress.apply(.stageEnd(name: "Mac host", ok: false, elapsed: 3, summary: "clang failed"))
        XCTAssertEqual(progress.overall, 0.9, accuracy: 1e-9)
    }

    func testCancelFails() {
        var progress = run(shaders + [.progress(fraction: 0.2, done: nil, total: nil, unit: nil, eta: 500)])
        progress.finish(success: false)
        XCTAssertEqual(progress.phase, .failed)
        XCTAssertEqual(progress.overall, 0.18, accuracy: 1e-9)
    }

    func testFinishingSecondsFromLog() {
        let log = """
        {"ev": "stage", "k": 5, "n": 7, "name": "Mac shaders", "step": "", "t": 1}
        {"ev": "progress", "k": 5, "frac": 0.5, "done": 1, "total": 2, "unit": "shaders", "eta": 30, "t": 2}
        {"ev": "stage_end", "k": 5, "name": "Mac shaders", "ok": true, "summary": "", "elapsed": 607, "t": 3}
        {"ev": "stage", "k": 6, "n": 7, "name": "Mac host", "step": "building", "t": 4}
        {"ev": "stage_end", "k": 6, "name": "Mac host", "ok": true, "summary": "", "elapsed": 10, "t": 5}
        {"ev": "stage", "k": 7, "n": 8, "name": "Pipeline archive", "step": "", "t": 6}
        {"ev": "stage_end", "k": 7, "name": "Pipeline archive", "ok": true, "summary": "", "elapsed": 79, "t": 7}
        {"ev": "stage", "k": 8, "n": 8, "name": "Mac app", "step": "", "t": 8}
        {"ev": "stage_end", "k": 8, "name": "Mac app", "ok": true, "summary": "", "elapsed": 61, "t": 9}
        """
        XCTAssertEqual(PortingProgress.finishingSeconds(inLog: log) ?? 0, 150, accuracy: 1e-9)
        let noShaders = """
        {"ev": "stage", "k": 1, "n": 2, "name": "Mac host", "step": "", "t": 1}
        {"ev": "stage_end", "k": 1, "name": "Mac host", "ok": true, "summary": "", "elapsed": 10, "t": 2}
        """
        XCTAssertNil(PortingProgress.finishingSeconds(inLog: noShaders))
    }

    /// The engine's line, as the first build after the engine update prints it for a game built before.
    private let cacheMove = BuildEvent.say("[15:00:00] moving the compile cache /Volumes/T7/Games/0100000000010000_build/shader/cache/cas.tar into one file read in place")

    func testShaderCacheUpdateIsVisibleWithoutInventingProgressOrAnETA() {
        var progress = run(beforeShaders)
        let fraction = progress.overall
        progress.apply(cacheMove)
        XCTAssertEqual(PortingETA.text(progress, lastFinishingSeconds: 60), "Updating shader cache")
        XCTAssertEqual(progress.overall, fraction)
        XCTAssertEqual(progress.phase, .preparing)
        progress.apply(.say("[15:00:01] another engine message"))
        XCTAssertEqual(PortingETA.text(progress, lastFinishingSeconds: nil), "Updating shader cache")
        progress.apply(.stage(k: 5, n: 8, name: "Mac shaders", step: "checking the inputs"))
        XCTAssertNil(PortingETA.text(progress, lastFinishingSeconds: nil))
    }

    func testShaderCacheUpdateClearsOnNextStepAndWhenTheBuildEnds() {
        var progress = run(beforeShaders + [cacheMove])
        XCTAssertEqual(PortingETA.text(progress, lastFinishingSeconds: nil), "Updating shader cache")
        progress.apply(.step("compiling"))
        XCTAssertNil(PortingETA.text(progress, lastFinishingSeconds: nil))
        progress.apply(cacheMove)
        progress.finish(success: false)
        XCTAssertNil(PortingETA.text(progress, lastFinishingSeconds: nil))
    }

    func testOlderCacheCleanupLineNoLongerShowsTheLabel() {
        let progress = run(beforeShaders + [.say("removing the shader cache of other chain versions")])
        XCTAssertNil(PortingETA.text(progress, lastFinishingSeconds: nil))
    }

    func testPipelineArchiveProgressAdvancesOverallAndSetsFinishingETA() {
        var progress = run(shaders + [
            .stageEnd(name: "Mac shaders", ok: true, elapsed: 607, summary: nil),
            .stage(k: 6, n: 8, name: "Mac host", step: "building"),
            .stageEnd(name: "Mac host", ok: true, elapsed: 10, summary: nil),
            .stage(k: 7, n: 8, name: "Pipeline archive", step: "applegpu_g13g")
        ])
        XCTAssertEqual(progress.phase, .finishing)
        XCTAssertEqual(progress.overall, 0.9 + 0.1 / 3, accuracy: 1e-9) // 93.3%
        XCTAssertNil(progress.finishingETA)

        // Halfway through Pipeline archive
        progress.apply(.progress(fraction: 0.5, done: 1000, total: 2000, unit: "pipelines", eta: 3600))
        XCTAssertEqual(progress.finishingETA, 3600)
        // overall should be 0.9 + 0.1 * (1 + 0.5) / 3 = 0.9 + 0.05 = 0.95 (95%)
        XCTAssertEqual(progress.overall, 0.95, accuracy: 1e-9)

        // Stage ends: clears finishingETA, overall becomes 0.9 + 0.1 * 2 / 3 = 0.9666...
        progress.apply(.stageEnd(name: "Pipeline archive", ok: true, elapsed: 120, summary: nil))
        XCTAssertNil(progress.finishingETA)
        XCTAssertEqual(progress.overall, 0.9 + 0.2 / 3, accuracy: 1e-9)
    }
}

final class BuildWarningTests: XCTestCase {
    func testEngineWarnIsRead() {
        XCTAssertEqual(BuildEventParser.parse(#"{"ev":"stage_end","k":7,"name":"Pipeline archive","ok":true,"summary":"failed, the app is packed without one","elapsed":3.1,"warn":true}"#),
                       .stageEnd(name: "Pipeline archive", ok: true, elapsed: 3.1, summary: "failed, the app is packed without one", warn: true))
        XCTAssertEqual(BuildEventParser.parse(#"{"ev":"stage_end","name":"pack","ok":true,"summary":"done","elapsed":1}"#),
                       .stageEnd(name: "pack", ok: true, elapsed: 1, summary: "done"), "older engines: no warning")
    }

    func testWarningCopy() {
        XCTAssertTrue(BuildWarningCopy.text(stage: "Pipeline archive", summary: "failed, the app is packed without one")
            .hasPrefix("The pipeline archive could not be made"))
        XCTAssertEqual(BuildWarningCopy.text(stage: "mac host", summary: " slow disk "),
                       "Mac host finished with a warning: slow disk. The log has the details.")
        XCTAssertEqual(BuildWarningCopy.text(stage: "pack", summary: nil), "Pack finished with a warning. The log has the details.")
    }

    func testAWarnedStageStillCountsAsFinished() {
        var progress = PortingProgress()
        progress.apply(.stage(k: 1, n: 2, name: "Mac shaders", step: nil))
        progress.apply(.stageEnd(name: "Mac shaders", ok: true, elapsed: 1, summary: nil))
        let before = progress.overall
        progress.apply(.stage(k: 2, n: 2, name: "Pipeline archive", step: nil))
        progress.apply(.stageEnd(name: "Pipeline archive", ok: true, elapsed: 1, summary: "failed", warn: true))
        XCTAssertGreaterThan(progress.overall, before)
    }
}
