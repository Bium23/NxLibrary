import AppKit
import SwiftUI

/// Reads the launch preference once; changing Settings never changes the current window's mode.
struct StartupWindowView: NSViewRepresentable {
    let fullscreen: Bool
    func makeNSView(context: Context) -> StartupWindowObserver { StartupWindowObserver(fullscreen: fullscreen) }
    func updateNSView(_ view: StartupWindowObserver, context: Context) {}
    static func dismantleNSView(_ view: StartupWindowObserver, coordinator: ()) { view.stop() }
}

final class StartupWindowObserver: NSView {
    private let fullscreen: Bool
    private var applied = false
    private var observer: NSObjectProtocol?

    init(fullscreen: Bool) { self.fullscreen = fullscreen; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard !applied, let window else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
            object: window, queue: .main) { [weak self] _ in self?.applyWhenReady() }
        applyWhenReady()
    }

    private func applyWhenReady() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.applied, let window = self.window, window.isVisible, window.isKeyWindow else { return }
            self.applied = true
            self.stop()
            if window.styleMask.contains(.fullScreen) != self.fullscreen { window.toggleFullScreen(nil) }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}
