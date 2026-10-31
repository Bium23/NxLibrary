import AppKit
import Combine
import NXLibraryCore

/// Which library games are running, and Resume and Close Game for them. The running set is
/// read from the system's process list (`RunningAppsTracker`) whenever it may have changed: on
/// launch and terminate notifications, on changes to `NSWorkspace.runningApplications`, and when
/// NX Library comes forward. Notifications alone miss a game whose launcher quits from its settings
/// window (it becomes a background process before it exits). A game that stops ends its play session.
@MainActor
final class RunningGameMonitor: ObservableObject {
    /// Time a game gets to quit after Close Game, in nanoseconds (5 s) before it is force-quit.
    static let forceQuitDelay: UInt64 = 5_000_000_000

    @Published private(set) var runningGameIDs: Set<UUID> = []

    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []
    private var sessions: PlaySessionStore?
    private var tracker: RunningAppsTracker?
    private var processListObservation: NSKeyValueObservation?
    private var activeToken: NSObjectProtocol?
    private var games: [PortedGame] = []
    private var closeTasks: [String: Task<Void, Never>] = [:]

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.center = center
    }

    /// Seeds the running set from the workspace, ends stale play sessions once, then follows launches and quits.
    func start(sessions: PlaySessionStore) {
        guard tokens.isEmpty else { return }
        self.sessions = sessions
        let tracker = RunningAppsTracker(snapshot: Self.runningBundleIDs)
        self.tracker = tracker
        sessions.reconcile(runningBundleIDs: tracker.running)
        recompute()
        tokens = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map {
            center.addObserver(forName: $0, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        activeToken = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        processListObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        for token in tokens { center.removeObserver(token) }
        tokens = []
        if let activeToken { NotificationCenter.default.removeObserver(activeToken) }
        activeToken = nil
        processListObservation?.invalidate()
        processListObservation = nil
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
              let app = Self.runningApplication(for: game) else {
            // Nothing to close: the game ended without being noticed. Read the process list again.
            refresh()
            return
        }
        app.terminate()
        closeTasks[bundleID]?.cancel()
        // The instance we asked to quit, not a fresh lookup: a relaunch within the delay must not be force-quit.
        closeTasks[bundleID] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.forceQuitDelay)
            guard !Task.isCancelled else { return }
            if !app.isTerminated { app.forceTerminate() }
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

    /// Every live process's bundle ID, background ones included.
    nonisolated private static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.compactMap(\.bundleIdentifier))
    }

    /// Reads the process list again; a game no longer in it ends its play session and any pending force-quit.
    func refresh() {
        guard let tracker else { return }
        for bundleID in tracker.refresh().ended {
            sessions?.end(bundleID: bundleID)
            closeTasks[bundleID]?.cancel()
            closeTasks[bundleID] = nil
        }
        recompute()
    }

    private func recompute() {
        let ids = RunningGames.matchingIDs(in: games, runningBundleIDs: tracker?.running ?? [])
        if ids != runningGameIDs { runningGameIDs = ids }
    }
}
