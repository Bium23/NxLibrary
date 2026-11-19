import AppKit
import NXLibraryCore
import QuartzCore
import os
import SwiftUI

/// The launch screen's own window, as Selene's launch cover: borderless and see-through (the screen fades in over
/// the library), over every app, the Dock and the menu bar, on whichever Space is in front, and never activated. The
/// game starts behind it, and Steam coming forward or macOS changing Space happens behind it, so Arcane never has
/// to take the front back. Shown on the screen of the window that hosts it while `state` is set; the content's
/// own fade-out runs before `state` clears.
struct LaunchCoverWindow<Content: View>: NSViewRepresentable {
    let state: LaunchOverlayState?
    let onPrepared: (UUID) -> Void
    @ViewBuilder let content: (LaunchOverlayState) -> Content

    func makeCoordinator() -> Cover { Cover() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        if let state {
            context.coordinator.show(AnyView(content(state)), for: state.game.id, on: view.window?.screen ?? NSScreen.main,
                                     prepared: onPrepared)
        } else {
            context.coordinator.close()
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Cover) { coordinator.close() }

    @MainActor
    final class Cover {
        private var panel: LaunchCoverPanel?
        private var host: LaunchCoverHostingView?
        private var gameID: UUID?

        func show(_ content: AnyView, for id: UUID, on screen: NSScreen?, prepared: @escaping (UUID) -> Void) {
            guard let screen else { return }
            if gameID == id, let panel, let host {
                host.rootView = content
                if panel.frame != screen.frame { panel.setFrame(screen.frame, display: true) }
                return
            }
            close()
            let panel = LaunchCoverPanel(frame: screen.frame)
            let host = LaunchCoverHostingView(rootView: content)
            panel.contentView = host
            self.panel = panel
            self.host = host
            gameID = id
            panel.orderFrontRegardless()
            // Leave SwiftUI's representable update before committing the panel. Steam can change Space as soon as
            // it receives Play, so send the hand-off only after submitting the ordered cover to the window server.
            DispatchQueue.main.async { [weak self, weak panel, weak host] in
                guard let self, let panel, let host, self.panel === panel, panel.isVisible else { return }
                host.layoutSubtreeIfNeeded()
                panel.displayIfNeeded()
                CATransaction.flush()
                LaunchCoverTrace.event("Cover submitted, active Space: \(panel.isOnActiveSpace)")
                prepared(id)
            }
        }

        func close() {
            panel?.orderOut(nil)
            panel?.contentView = nil
            panel = nil
            host = nil
            gameID = nil
        }
    }
}

/// Local development diagnostics for the cover hand-off, without game or account identifiers.
enum LaunchCoverTrace {
    private static let log = Logger(subsystem: "local.nxlibrary.development", category: "launch-cover")

    static func event(_ message: String) {
        guard AppData.profile.isDevelopment else { return }
        log.notice("\(message, privacy: .public)")
    }
}

/// A click on the screen dismisses it at once: the first click counts although Arcane may not be active.
final class LaunchCoverHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class LaunchCoverPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Over the Dock and the menu bar (on the desktop Space Steam may take the screen to).
        level = .statusBar
        // Every Space, full-screen ones included, and left in place by Mission Control. When a game opens full screen
        // the screen rides along into the game's Space and covers it until the game draws, instead of the desktop
        // picture showing there: the maintainer's choice over a screen that stays on Arcane's Space.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // A panel hides when its app is not active by default; Arcane rarely is while a game starts.
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
