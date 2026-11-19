#!/usr/bin/env python3
"""Exercise entrance input and drawable readiness with no windows, GPU or player data.

Compile the actual receiver, input prelude and render/reveal methods. Only their
surrounding view state and Metal submission/presentation boundary are substituted.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / '.build/debug'


def declaration(path, signature):
    source = (ROOT / path).read_text()
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


host = r'''
import Foundation
import NXLibraryCore

typealias CFTimeInterval = Double
func CACurrentMediaTime() -> Double { 0 }
@MainActor enum LaunchReveal {
    static var frames = 0
    static func moonlightShown() { frames += 1 }
}
final class CAMetalDrawable {
    private var handlers: [(CAMetalDrawable) -> Void] = []
    func addPresentedHandler(_ handler: @escaping (CAMetalDrawable) -> Void) { handlers.append(handler) }
    func present() { let callbacks = handlers; handlers = []; callbacks.forEach { $0(self) } }
}
final class CAMetalLayer {
    var drawableSize = CGSize(width: 1920, height: 1080)
}
final class MoonlightEngine {
    static let breathPeriod = 1.0
    static func uniforms(width: Int, height: Int, time: Float, breath: Float, colors: Int) -> Int { 0 }
    var submissions = 0
    func render(into drawable: CAMetalDrawable, uniforms: Int) { submissions += 1 }
}
final class MoonlightHost {
    struct State {
        var moving = false
        var lastTick: Double?
        var clock = 0.0
        var from: Int?
        var stillPending = false
    }
    var state = State()
    let lock = NSLock()
    let metalLayer = CAMetalLayer()
    let engine = MoonlightEngine()
    static var firstFrameAnnounced = false
    static let firstFrameLock = NSLock()
    static func blended(_ state: State, at now: Double) -> Int { 0 }
    func blending(at now: Double) -> Bool { false }
    func updateLink() {}
    func traceFirstPresentation(_ drawable: CAMetalDrawable) {}
    func draw(_ drawable: CAMetalDrawable) { renderFrame(at: 1, drawable: drawable) }
    // ACTUAL_RENDER
    // ACTUAL_READY
}
final class InputState {
    var alertMessage: String?
    var settingsNotice: Int?
    var isWelcomeOpen = false
    var showSetupCheck = false
    var isWindowSettling = true
}
final class InputHost {
    let viewModel = InputState()
    var entrance = SpotlightEntrance.Phase.covered
    var handled: [GamepadAction] = []
    // ACTUAL_OVERLAID
    // ACTUAL_COVERED
    func landEntrance() { entrance.land() }
    func handle(_ action: GamepadAction) {
        // ACTUAL_INPUT_PRELUDE
        handled.append(action)
    }
    func receive(_ note: Notification) {
        // ACTUAL_RECEIVER
    }
}

@main struct Check {
    @MainActor static func main() async {
        var failures = 0
        func require(_ ok: @autoclosure () -> Bool, _ message: String) {
            if !ok() { failures += 1; print("FAIL: " + message) }
        }
        for phase: SpotlightEntrance.Phase in [.covered, .waiting, .playing] {
            let input = InputHost()
            input.entrance = phase
            input.receive(Notification(name: .init("fixture"), object: GamepadAction.confirm))
            require(input.handled.isEmpty && input.entrance == phase,
                    "A press during the entrance must neither act nor skip it (phase \(phase))")
        }
        let landed = InputHost()
        landed.entrance = .landed
        landed.receive(Notification(name: .init("fixture"), object: GamepadAction.confirm))
        require(landed.handled == [.confirm], "Once landed, a press acts as usual")
        for setup in [false, true] {
            let input = InputHost()
            input.viewModel.showSetupCheck = setup
            input.viewModel.isWelcomeOpen = !setup
            input.receive(Notification(name: .init("fixture"), object: GamepadAction.confirm))
            require(input.handled.isEmpty && input.entrance == .covered,
                    "A real welcome/Setup cover must still block Spotlight input")
        }
        do {
            MoonlightHost.firstFrameAnnounced = false
            LaunchReveal.frames = 0
            let renderer = MoonlightHost()
            let drawable = CAMetalDrawable()
            renderer.draw(drawable)
            for _ in 0..<20 { await Task.yield() }
            require(renderer.engine.submissions == 1 && LaunchReveal.frames == 0,
                    "Submitting a frame must not announce presentation")
            drawable.present()
            for _ in 0..<100 where LaunchReveal.frames == 0 { await Task.yield() }
            require(LaunchReveal.frames == 1, "The first presented drawable must release the reveal gate")
            let another = CAMetalDrawable()
            renderer.draw(another)
            another.present()
            for _ in 0..<20 { await Task.yield() }
            require(LaunchReveal.frames == 1, "Later frames must not release the reveal gate twice")
        }
        if failures > 0 { exit(1) }
        print("Entrance checks passed: no skip during the entrance, covers, presentation readiness of the link's drawable.")
    }
}
'''
entrance = 'Sources/NXLibrary/Views/Spotlight/SpotlightView+Entrance.swift'
renderer = 'Sources/NXLibrary/Views/Theme/MoonlightRenderer.swift'
for marker, path, signature in (
    ('// ACTUAL_OVERLAID', entrance, '    var isOverlaid:'),
    ('// ACTUAL_COVERED', entrance, '    var isCovered:'),
    ('// ACTUAL_RENDER', renderer, '    private func renderFrame('),
    ('// ACTUAL_READY', renderer, '    private static func announceFirstFrame('),
):
    host = host.replace(marker, declaration(path, signature))
receiver = declaration('Sources/NXLibrary/Views/Spotlight/SpotlightView.swift',
                       '        .onReceive(NotificationCenter.default.publisher(for: .nxSpotlightGamepadAction))')
host = host.replace('// ACTUAL_RECEIVER', receiver.split('{ note in', 1)[1].rsplit('}', 1)[0])
handler = declaration('Sources/NXLibrary/Views/Spotlight/SpotlightView+Input.swift',
                      '    func handle(_ action: GamepadAction)')
prelude = handler[handler.index('{') + 1:handler.index('        if viewer != nil')]
host = host.replace('// ACTUAL_INPUT_PRELUDE', prelude)
with tempfile.TemporaryDirectory(prefix='entrance-check-') as folder:
    scratch = Path(folder)
    swift = scratch / 'check.swift'
    swift.write_text(host)
    executable = scratch / 'check'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-I', str(BIN), str(swift),
                    str(ROOT / 'Sources/NXLibrary/Models/GamepadType.swift'),
                    str(BIN / 'NXLibraryCore.o'), '-o', str(executable)], cwd=ROOT, check=True)
    subprocess.run([str(executable)], env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)), check=True)
