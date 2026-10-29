import AppKit
import Combine
import NXLibraryCore

/// Which library games are running, and Resume and Close Game for them. It is the
/// one observer of the workspace's launch and terminate notifications; a terminated
/// game also ends its play session.
@MainActor
final class RunningGameMonitor: ObservableObject {
    /// Seconds a game gets to quit after Close Game before it is force-quit.
    static let forceQuitDelay: UInt64 = 5_000_000_000

    @Published private(set) var runningGameIDs: Set<UUID> = []

    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []
    private var sessions: PlaySessionStore?
    private var runningBundleIDs: Set<String> = []
    private var games: [PortedGame] = []
    private var closeTasks: [String: Task<Void, Never>] = [:]

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.center = center
    }

    /// Seeds the running set from the workspace, ends stale play sessions once, then follows launches and quits.
    func start(sessions: PlaySessionStore) {
        guard tokens.isEmpty else { return }
        self.sessions = sessions
        runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        sessions.reconcile(runningBundleIDs: runningBundleIDs)
        recompute()
        tokens = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                               object: nil, queue: .main) { [weak self] note in
                let bundleID = Self.bundleID(of: note)
                Task { @MainActor in self?.appLaunched(bundleID: bundleID) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                               object: nil, queue: .main) { [weak self] note in
                let bundleID = Self.bundleID(of: note)
                Task { @MainActor in self?.appTerminated(bundleID: bundleID) }
            }
        ]
    }

    func stop() {
        for token in tokens { center.removeObserver(token) }
        tokens = []
        for task in closeTasks.values { task.cancel() }
        closeTasks = [:]
    }

    /// The library changed: new and removed games are matched again.
    func setGames(_ games: [PortedGame]) {
        self.games = games
        recompute()
    }

    func isRunning(_ game: PortedGame) -> Bool {
        runningGameIDs.contains(game.id)
    }

    /// Brings a running game's app forward. Never starts a second copy.
    func resume(_ game: PortedGame) {
        guard let app = Self.runningApplication(for: game) else { return }
        Self.activate(app)
    }

    /// Asks the game to quit; after 5 s it is force-quit if it is still running.
    /// The caller asks the player first (Close Game confirmation).
    func close(_ game: PortedGame) {
        guard let bundleID = game.effectiveBundleId,
              let app = Self.runningApplication(for: game) else { return }
        app.terminate()
        closeTasks[bundleID]?.cancel()
        closeTasks[bundleID] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.forceQuitDelay)
            guard !Task.isCancelled else { return }
            if let stuck = Self.runningApplication(bundleID: bundleID) {
                stuck.forceTerminate()
            }
            self?.closeTasks[bundleID] = nil
        }
    }

    /// The live process of a game, if one is running.
    nonisolated static func runningApplication(for game: PortedGame) -> NSRunningApplication? {
        guard let bundleID = game.effectiveBundleId else { return nil }
        return runningApplication(bundleID: bundleID)
    }

    nonisolated static func runningApplication(bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }

    /// Activates an app. macOS 14 replaces the options call with cooperative activation.
    nonisolated static func activate(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateAllWindows])
        }
    }

    // MARK: - Notifications

    nonisolated private static func bundleID(of note: Notification) -> String? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }

    private func appLaunched(bundleID: String?) {
        guard let bundleID, !bundleID.isEmpty else { return }
        runningBundleIDs.insert(bundleID)
        recompute()
    }

    private func appTerminated(bundleID: String?) {
        sessions?.end(bundleID: bundleID)
        guard let bundleID, !bundleID.isEmpty else { return }
        runningBundleIDs.remove(bundleID)
        closeTasks[bundleID]?.cancel()
        closeTasks[bundleID] = nil
        recompute()
    }

    private func recompute() {
        let ids = RunningGames.matchingIDs(in: games, runningBundleIDs: runningBundleIDs)
        if ids != runningGameIDs { runningGameIDs = ids }
    }
}
