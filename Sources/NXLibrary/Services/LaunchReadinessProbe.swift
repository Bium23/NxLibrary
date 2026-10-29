import AppKit
import CoreGraphics

/// Waits for a launched game to put a real window on screen. Reads only each
/// window's owner PID, bounds and alpha, which needs no Screen Recording permission.
final class LaunchReadinessProbe {
    private let interval: UInt64 = 250_000_000

    /// True once a window of `bundleID` at least 320×240 and visible is on screen;
    /// false on timeout or cancellation.
    func waitUntilVisible(bundleID: String, timeout: TimeInterval = 60) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !Task.isCancelled {
            if Self.hasVisibleWindow(bundleID: bundleID) { return true }
            try? await Task.sleep(nanoseconds: interval)
        }
        return false
    }

    static func hasVisibleWindow(bundleID: String) -> Bool {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .map(\.processIdentifier))
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
