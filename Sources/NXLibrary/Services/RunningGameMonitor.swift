import AppKit
import Combine
import NXLibraryCore

/// Which library games are running, and Resume and Close Game for them. The running set is
/// read from the system's process list (`RunningAppsTracker`) whenever it may have changed: on
/// launch and terminate notifications, on changes to `NSWorkspace.runningApplications`, and when
/// NX Library comes forward. Notifications alone miss a game whose launcher quits from its settings
/// window (it becomes a background process before it exits). A game that stops ends its play session, and when it
/// quit in front with no other library game open, NX Library comes back to the front (`GameFocus`).
@MainActor
final class RunningGameMonitor: ObservableObject {
    /// Time a game gets to quit after Close Game, in nanoseconds (5 s) before it is force-quit.
    static let forceQuitDelay: UInt64 = 5_000_000_000

    @Published private(set) var runningGameIDs: Set<UUID> = []
    /// The latest play session a game's quit ended, for the session card (nil when it was too short for one).
    @Published private(set) var endedSession: SessionSummary?

    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []
    private var sessions: PlaySessionStore?
    private var tracker: RunningAppsTracker?
    private var processListObservation: NSKeyValueObservation?
    private var activeToken: NSObjectProtocol?
    private var games: [PortedGame] = []
    private var closeTasks: [String: Task<Void, Never>] = [:]
    private var focus = GameFocus()
    private var focusToken: NSObjectProtocol?

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
        focusToken = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                        object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            Task { @MainActor in self?.activated(bundleID) }
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
        if let focusToken { center.removeObserver(focusToken) }
        focusToken = nil
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
        let ended = tracker.refresh().ended
        var comesForward = false
        for bundleID in ended {
            let others = libraryBundleIDs.intersection(tracker.running).subtracting(ended)
            if focus.gameEnded(bundleID, othersRunning: !others.isEmpty) { comesForward = true }
            for session in sessions?.end(bundleID: bundleID) ?? [] {
                guard let game = games.first(where: { $0.id == session.gameID }),
                      let summary = SessionSummary(session: session, game: game,
                                                   total: sessions?.totalDuration(for: game.id) ?? 0) else { continue }
                endedSession = summary
            }
            closeTasks[bundleID]?.cancel()
            closeTasks[bundleID] = nil
        }
        recompute()
        if comesForward { comeForward() }
    }

    private var libraryBundleIDs: Set<String> { Set(games.compactMap(\.effectiveBundleId)) }

    /// A library game in front is noted; another app that is still in front a second later, while that game runs,
    /// means the player left the game (an app macOS brings forward as a game quits does not count).
    private func activated(_ bundleID: String?) {
        if let bundleID, libraryBundleIDs.contains(bundleID) {
            focus.gameCameForward(bundleID)
            return
        }
        guard let game = focus.gameInFront else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, Self.runningApplication(bundleID: game) != nil,
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier != game else { return }
            self.focus.otherAppStayedForward(whileRunning: game)
        }
    }

    /// NX Library back in front after the game in front quit. macOS often makes NX Library the active app by itself
    /// as the game quits, but leaves the screen on the desktop while NX Library's full-screen window stays in its own
    /// Space: activating alone shows nothing. So the main window is also brought forward, which takes macOS to its
    /// Space. `ignoringOtherApps: true` covers the case where macOS put another app in front instead. Checked once
    /// more after the Space switch; never over a library game.
    private func comeForward() {
        Self.bringForward(Self.mainWindow)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            let window = Self.mainWindow
            guard let self, !NSApp.isActive || window?.isOnActiveSpace == false else { return }
            if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               self.libraryBundleIDs.contains(front) { return }
            Self.bringForward(window)
        }
    }

    /// NX Library's main window: the visible one that can be main (not a panel or the menu bar's).
    private static var mainWindow: NSWindow? {
        NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }

    private static func bringForward(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func recompute() {
        let ids = RunningGames.matchingIDs(in: games, runningBundleIDs: tracker?.running ?? [])
        if ids != runningGameIDs { runningGameIDs = ids }
    }
}
