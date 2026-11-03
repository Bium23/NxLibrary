import AppKit
import SwiftUI
import NXLibraryCore

/// Observes only the launcher's window; every event keeps its normal destination.
struct FullscreenCursorView: NSViewRepresentable {
    var suspended: Bool

    func makeNSView(context: Context) -> CursorWindowView { CursorWindowView() }
    func updateNSView(_ view: CursorWindowView, context: Context) { view.suspended = suspended }
    static func dismantleNSView(_ view: CursorWindowView, coordinator: ()) { view.stop() }
}

final class CursorWindowView: NSView {
    var suspended = true {
        didSet { if oldValue != suspended { reset() } }
    }
    private var state = CursorIdleState()
    private var appliedHidden = false
    private var timer: Timer?
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private weak var observedWindow: NSWindow?
    private var previousMouseMovedEvents = false
    private var menuTracking = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard let window else { return }
        observedWindow = window
        previousMouseMovedEvents = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown,
            .otherMouseDown, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.reset()
            return event
        }
        // Native panels and focus/fullscreen transitions restore the cursor immediately.
        let names: [Notification.Name] = [NSApplication.didResignActiveNotification,
            NSApplication.didBecomeActiveNotification, NSApplication.willTerminateNotification,
            NSWindow.didResignKeyNotification, NSWindow.didBecomeKeyNotification,
            NSWindow.willExitFullScreenNotification, NSWindow.didEnterFullScreenNotification,
            NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification,
            NSWindow.didMiniaturizeNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reset()
            }
        }
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.menuTracking = name == NSMenu.didBeginTrackingNotification
                self?.reset()
            })
        }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        menuTracking = false
        observedWindow?.acceptsMouseMovedEvents = previousMouseMovedEvents
        observedWindow = nil
        _ = state.update(now: ProcessInfo.processInfo.systemUptime, eligible: false)
        apply(hidden: false)
    }

    private func reset() {
        state.mouseActivity(now: ProcessInfo.processInfo.systemUptime)
        apply(hidden: false)
    }

    private func tick() {
        var eligible = false
        if let window, let content = window.contentView {
            let pointer = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            eligible = !suspended && !menuTracking && NSApp.isActive && window.isKeyWindow && window.isVisible
                && window.styleMask.contains(.fullScreen) && window.attachedSheet == nil
                && NSApp.modalWindow == nil && !(window.firstResponder is NSText)
                && content.bounds.contains(pointer)
        }
        apply(hidden: state.update(now: ProcessInfo.processInfo.systemUptime, eligible: eligible))
    }

    private func apply(hidden: Bool) {
        guard hidden != appliedHidden else { return }
        NSCursor.setHiddenUntilMouseMoves(hidden)
        appliedHidden = hidden
    }
}
