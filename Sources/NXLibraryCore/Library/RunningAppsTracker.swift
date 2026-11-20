import Foundation

/// The bundle IDs running now, read from a snapshot of the system's processes (NSWorkspace.runningApplications) each
/// time something may have changed. Notifications alone miss apps: a game's launcher that quits from its settings
/// window becomes a background process before it exits, and macOS posts no "terminated" for it.
public final class RunningAppsTracker {
    private let snapshot: () -> Set<String>
    public private(set) var running: Set<String>

    public init(snapshot: @escaping () -> Set<String>) {
        self.snapshot = snapshot
        running = snapshot()
    }

    /// Reads the snapshot again: what started and what ended since the last read.
    @discardableResult
    public func refresh() -> (started: Set<String>, ended: Set<String>) {
        let now = snapshot()
        defer { running = now }
        return (now.subtracting(running), running.subtracting(now))
    }
}
