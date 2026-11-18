import AppKit
import SwiftUI

/// The app's window stays transparent from its first frame until the moonlight has shown one, then fades in, and
/// only then may it go full screen. Without the wait the window opened black and macOS animated its fullscreen
/// transition from a picture of that black window, because the moonlight draws its first frame on its own thread a
/// moment after the library appears. `limit` bounds the wait (a wallpaper with no moonlight, an error screen).
@MainActor
enum LaunchReveal {
    static let limit: TimeInterval = 1
    static let fade: TimeInterval = 0.25
    private static weak var window: NSWindow?
    private static var held = false
    private static var shown = false
    private static var done = false
    private static var waiting: [() -> Void] = []

    /// Once per launch, on the window's first appearance.
    static func hold(_ window: NSWindow) {
        guard !held, !shown else { return }
        held = true
        self.window = window
        window.alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + limit) { show() }
    }

    /// The first moonlight frame of this launch is on screen.
    static func moonlightShown() { show() }

    /// The window fades in once its first frame is ready, or its bounded wait ends.
    static func show() {
        guard !shown else { return }
        shown = true
        guard let window, held else { return finish() }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fade
            window.animator().alphaValue = 1
        }, completionHandler: { Task { @MainActor in finish() } })
    }

    /// Runs `action` once the window has faded in (at once when it already has).
    static func whenShown(_ action: @escaping () -> Void) {
        if done { return action() }
        waiting.append(action)
    }

    private static func finish() {
        window?.alphaValue = 1
        done = true
        let actions = waiting
        waiting = []
        actions.forEach { $0() }
    }
}

/// Holds the window it lands in transparent until `LaunchReveal` shows it.
struct LaunchRevealHold: NSViewRepresentable {
    func makeNSView(context: Context) -> LaunchRevealHoldView { LaunchRevealHoldView() }
    func updateNSView(_ view: LaunchRevealHoldView, context: Context) {}
}

final class LaunchRevealHoldView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { MainActor.assumeIsolated { LaunchReveal.hold(window) } }
    }
}
