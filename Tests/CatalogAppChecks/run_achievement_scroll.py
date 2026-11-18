#!/usr/bin/env python3
"""Exercise actual achievement list/model lifecycle in an offscreen SwiftUI host.

No windows, screenshots or UI automation. Graphics and external data use small
stand-ins; the list, selection model, scroll model and geometry group are real.
Run after swift test on macOS.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / '.build/debug'
source = (ROOT / 'Sources/NXLibrary/Views/Spotlight/AchievementsScreen.swift').read_text()
start = source.index('private struct AchievementsList: View')
end = source.index('\n/// The trophies,', start)

host = r'''
import AppKit
import SwiftUI
import NXLibraryCore

struct ProbeCanvas {
    var scale: CGFloat = 1
    func u(_ value: CGFloat) -> CGFloat { value * scale }
}
private struct CanvasKey: EnvironmentKey { static let defaultValue = ProbeCanvas() }
private struct MotionKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var seleneCanvas: ProbeCanvas {
        get { self[CanvasKey.self] } set { self[CanvasKey.self] = newValue }
    }
    var seleneReduceMotion: Bool {
        get { self[MotionKey.self] } set { self[MotionKey.self] = newValue }
    }
}
extension View {
    func seleneFont(_ size: CGFloat) -> some View { font(.system(size: size)) }
}
enum SeleneTheme { static let ink60 = Color.gray }
enum DetailScroll { static let glide = Animation.spring(response: 0.3, dampingFraction: 1) }
enum AchievementsScreen {
    static let rowHeight: CGFloat = 96, rowSpacing: CGFloat = 16, ring: CGFloat = 6
    static let listWidth: CGFloat = 1700, topFade: CGFloat = 40
    static let bottomFade: CGFloat = 110, hintsBand: CGFloat = 84, bottomRoom: CGFloat = 194
}
struct AchievementsScreenRow: View {
    let row: AchievementRow
    let appID: UInt32
    let focused: Bool
    var body: some View { Text(row.name).frame(width: 1700, height: 96) }
}
let summary = AchievementSummary(achievements: (0..<41).map {
    SteamAchievement(apiName: "generated-\($0)", name: "Row \($0)", description: "Generated fixture",
                     hidden: false, icon: nil, grayIcon: nil, unlockedAt: nil)
}, percents: [:])
let rows = summary.rows(.all)

@MainActor final class Owner: ObservableObject {
    @Published var model: AchievementsScreenModel? = AchievementsScreenModel(ids: rows.map(\.id))
    @Published var reducedMotion = false
    @Published var height: CGFloat = 400
}
struct ScreenHost: View {
    @ObservedObject var model: AchievementsScreenModel
    var body: some View {
        ZStack {
            AchievementsList(scroll: model.scroll, model: model, rows: rows, focused: model.state.index,
                             appID: 42, onFocus: { model.focus($0) })
            if model.state.isDetailOpen { Color.black.opacity(0.5).transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.2), value: model.state.isDetailOpen)
    }
}
struct Probe: View {
    @ObservedObject var owner: Owner
    var body: some View {
        ZStack {
            if let model = owner.model { ScreenHost(model: model).transition(.opacity) }
        }
        .frame(width: 1712, height: owner.height)
        .environment(\.seleneReduceMotion, owner.reducedMotion)
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.32), value: owner.model != nil)
    }
}

@main struct Check {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var failures = 0
        func require(_ condition: Bool, _ message: String) {
            if !condition { failures += 1; print("FAIL: " + message) }
        }
        for reducedMotion in [false, true] {
            let owner = Owner()
            owner.reducedMotion = reducedMotion
            let host = NSHostingView(rootView: Probe(owner: owner))
            host.frame = CGRect(x: 0, y: 0, width: 1712, height: 400)
            func settle(_ steps: Int = 10) {
                for _ in 0..<steps {
                    _ = host.fittingSize
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                }
            }
            func walk(_ label: String) {
                let model = owner.model!
                for _ in 0..<12 { _ = model.handle(.navigateDown, summary: summary) }
                settle()
                require(model.state.index == 12, label + ": selection reaches row 12")
                require(model.scroll.state.content > 4000 && model.scroll.state.visible == owner.height,
                        label + ": current list receives its geometry")
                require(model.scroll.state.offset > 1000, label + ": viewport follows selection")
            }
            settle()
            walk("First open")

            owner.model!.focus(0)
            for _ in 0..<5 {
                _ = owner.model!.handle(.confirm, summary: summary)
                settle(1)
                _ = owner.model!.handle(.cancel, summary: summary)
                settle(1)
            }
            walk("Repeated first-row details")

            // The outgoing view is still in its 320 ms transition when the new model arrives.
            for index in 0..<3 {
                owner.model = nil
                settle(1)
                owner.model = AchievementsScreenModel(ids: rows.map(\.id))
                settle()
                walk("Rapid reopening \(index), reduced motion \(reducedMotion)")
            }

            owner.model = nil
            settle(40)
            owner.model = AchievementsScreenModel(ids: rows.map(\.id))
            settle()
            walk("Reopening after transition")
            owner.height = 320
            host.frame.size.height = 320
            settle()
            require(owner.model!.scroll.state.visible == 320, "Resizing reports the new viewport")
            require(host.window == nil, "Probe must never display a window")
        }
        if failures > 0 { exit(1) }
        print("Achievement scroll checks passed: first-row details, rapid/settled reopening, resize and reduced motion. No windows displayed.")
    }
}
''' + source[start:end]

with tempfile.TemporaryDirectory(prefix='achievement-scroll-check-') as folder:
    scratch = Path(folder)
    swift = scratch / 'check.swift'
    swift.write_text(host)
    executable = scratch / 'check'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-I', str(BIN), str(swift),
                    str(ROOT / 'Sources/NXLibrary/Models/GamepadType.swift'),
                    str(ROOT / 'Sources/NXLibrary/ViewModels/AchievementsScreenModel.swift'),
                    str(ROOT / 'Sources/NXLibrary/ViewModels/ListScroll.swift'),
                    str(ROOT / 'Sources/NXLibrary/Views/Components/GlideGroup.swift'),
                    str(BIN / 'NXLibraryCore.o'), '-o', str(executable)], cwd=ROOT, check=True)
    subprocess.run([str(executable)], check=True,
                   env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)))
