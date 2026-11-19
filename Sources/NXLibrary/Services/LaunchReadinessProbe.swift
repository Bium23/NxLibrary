import AppKit
import CoreGraphics

/// Waits for a launched game to put a real window on screen. Reads only each
/// window's owner PID, bounds and alpha, which needs no Screen Recording permission.
final class LaunchReadinessProbe {
    private let interval: UInt64 = 250_000_000

    /// True once a window of `bundleID` at least 320×240 and visible is on screen;
    /// false on timeout or cancellation.
    func waitUntilVisible(bundleID: String, timeout: TimeInterval = 60) async -> Bool {
        await waitUntil(timeout: timeout) { Self.hasVisibleWindow(bundleID: bundleID) }
    }

    /// The same for one process: a Steam game, which Steam starts and Arcane knows by its pid.
    func waitUntilVisible(pid: pid_t, timeout: TimeInterval = 60) async -> Bool {
        await waitUntil(timeout: timeout) { Self.hasVisibleWindow(pids: [pid]) }
    }

    private func waitUntil(timeout: TimeInterval, _ visible: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !Task.isCancelled {
            if visible() { return true }
            try? await Task.sleep(nanoseconds: interval)
        }
        return false
    }

    static func hasVisibleWindow(bundleID: String) -> Bool {
        hasVisibleWindow(pids: Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .map(\.processIdentifier)))
    }

    static func hasVisibleWindow(pids: Set<pid_t>) -> Bool {
        guard !pids.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return false
            }
            return bounds.width >= 320 && bounds.height >= 240
        }
    }
}
