import AppKit
import SwiftUI

/// The launch screen's own window, as Selene's launch cover: borderless and see-through (the screen fades in over
/// the library), over every app, the Dock and the menu bar, on whichever Space is in front, and never activated. The
/// game starts behind it, and Steam coming forward or macOS changing Space happens behind it, so NX Library never has
/// to take the front back. Shown on the screen of the window that hosts it while `state` is set; the content's
/// own fade-out runs before `state` clears.
struct LaunchCoverWindow<Content: View>: NSViewRepresentable {
    let state: LaunchOverlayState?
    @ViewBuilder let content: (LaunchOverlayState) -> Content

    func makeCoordinator() -> Cover { Cover() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        if let state {
            context.coordinator.show(AnyView(content(state)), on: view.window?.screen ?? NSScreen.main)
        } else {
            context.coordinator.close()
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Cover) { coordinator.close() }

    @MainActor
    final class Cover {
        private var panel: LaunchCoverPanel?
        private var host: LaunchCoverHostingView?

        func show(_ content: AnyView, on screen: NSScreen?) {
            guard let screen else { return }
            if let panel, let host {
                host.rootView = content
                if panel.frame != screen.frame { panel.setFrame(screen.frame, display: true) }
                return
            }
            let panel = LaunchCoverPanel(frame: screen.frame)
            let host = LaunchCoverHostingView(rootView: content)
            panel.contentView = host
            panel.orderFrontRegardless()
            self.panel = panel
            self.host = host
        }

        func close() {
            panel?.orderOut(nil)
            panel?.contentView = nil
            panel = nil
            host = nil
        }
    }
}

/// A click on the screen dismisses it at once: the first click counts although NX Library may not be active.
final class LaunchCoverHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class LaunchCoverPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Over the Dock and the menu bar (on the desktop Space Steam may take the screen to).
        level = .statusBar
        // Every Space, full-screen ones included, and left in place by Mission Control.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // A panel hides when its app is not active by default; NX Library rarely is while a game starts.
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
