import AppKit
import Combine
import NXLibraryCore

/// Play for Steam games and their real sessions (`SteamPlayState`). Play sends `steam://run/<AppID>`
/// to the registered Steam client only; it never opens the game's app itself. The process list is
/// read on launches, quits and the app list changing, and every 30 s for waits and heartbeats: the
/// installation's own app starts a session, its exit ends it, Steam staying open does not count.
/// The catalog is not written here; only `PlaySessionStore` is.
///
/// Play shows the launch screen (`launchScreen`) while the game is on its way, as for an nxnative game. The screen
/// has its own window over every app (`LaunchCoverWindow`), so Steam coming forward, or macOS changing Space,
/// happens behind it and NX Library never takes the front back. The screen leaves once the game's window is up (the
/// game is brought forward), when Play ends, as soon as Steam's log says the launch waits on a question for the
/// player (`SteamLaunchQuestionWatch`), or past the wait's patience (`SteamBackgroundLaunch`: 15 s with Steam open,
/// 45 s when Play starts it); in those last two cases Steam is brought forward and the head says to check it.
///
/// With "Keep Steam in the background", a Steam that Play starts opens with `-silent -nofriendsui`, and an open
/// Steam is hidden while the game is on its way; once Play is over, Steam comes back only if it was in view
/// before, and one that was out of view goes back out of view.
///
/// When a game whose Play was pressed here quits while it was the app in front and no other library game is
/// open, NX Library comes back to the front (`SteamReturnFocus`, `LibraryWindow`); a game started from Steam
/// leaves the player in Steam.
@MainActor
final class SteamPlayCoordinator: ObservableObject {
    static let shared = SteamPlayCoordinator()
    nonisolated static let steamBundleID = "com.valvesoftware.steam"
    private static let tick: TimeInterval = 30

    @Published private(set) var states: [UUID: SteamPlayState] = [:]
    /// Waits past their patience: Steam is back in view and may need the player.
    @Published private(set) var late: Set<UUID> = []
    /// The launch screen of the game whose Play was pressed here; `ready` makes it leave.
    struct LaunchScreen: Equatable {
        let gameID: UUID
        var ready = false
    }
    @Published private(set) var launchScreen: LaunchScreen?
    /// The latest Steam session that ended, for the session card (as `RunningGameMonitor.endedSession`).
    @Published private(set) var endedSession: SessionSummary?

    private var games: [CatalogGame] = []
    private var steamEnabled = false
    private var sessions: PlaySessionStore?
    private var settings: AppSettingsStore?
    /// Background launches in progress, with whether Steam was in view before Play.
    private var backgrounds: [UUID: Bool] = [:]
    private var tokens: [NSObjectProtocol] = []
    /// Each running app's paths as the system gives them and resolved, by pid: resolved once while it lives.
    private var canonicalProcesses: [Int32: (observed: NativeProcessObservation, canonical: NativeProcessObservation)] = [:]
    private var listObservation: NSKeyValueObservation?
    private var timer: Timer?
    private var returnFocus = SteamReturnFocus()
    /// When the coordinator began watching: a game launched before then is not a new start for Spotlight.
    private var watchingSince = Date.distantPast
    private var hideAgain: Task<Void, Never>?
    /// Each wait's patience, set when Play hands the game to Steam.
    private var patience: [UUID: TimeInterval] = [:]
    /// Waits for the started game's window, for the launch screen.
    private var readiness: Task<Void, Never>?
    /// The library's nxnative games, set by the shell: one that is open keeps NX Library from coming forward.
    weak var nativeGames: RunningGameMonitor?
    /// Whether a launch screen (any game's) is on screen, set by the shell: Play waits until it has gone.
    var isLaunchScreenShowing: () -> Bool = { false }
    /// Steam's folder while the Steam source is enabled: its log says when a launch waits on the player.
    private var steamRoot: URL?
    /// The game Play last handed to Steam, read in Steam's log for a question while it is on its way
    /// (`questionTimer`), off the main thread and one look at a time.
    private var questionWatch: (gameID: UUID, watch: SteamLaunchQuestionWatch)?
    private var questionTimer: Timer?
    private var questionLooking = false
    /// Bumps with each new watch, so a look still reading for an older one is dropped.
    private var questionGeneration = 0
    private static let questionLook: TimeInterval = 0.5

    /// A Steam game's own app is running.
    var hasRunningGame: Bool { states.values.contains { if case .running = $0.phase { return true }; return false } }

    func isRunningGame(pid: Int32) -> Bool {
        states.values.contains { $0.phase == .running(pid: pid) }
    }

    func phase(of game: CatalogGame) -> SteamPlayState.Phase { states[game.id]?.phase ?? .idle }
    func isRunning(_ game: CatalogGame) -> Bool { if case .running = phase(of: game) { return true }; return false }
    /// One available, recognized installation in an enabled source: what Play needs.
    func canPlay(_ game: CatalogGame) -> Bool {
        CatalogGamePresentation(game: game, sourceEnabled: steamEnabled).launchTarget != nil
    }

    /// Steam is still installing it: the first pill and A open Steam's Downloads instead of Play.
    func isDownloading(_ game: CatalogGame) -> Bool {
        CatalogGamePresentation(game: game, sourceEnabled: steamEnabled).isDownloading
    }

    /// Opens Steam on its Downloads page; nothing without Valve's client.
    func openDownloads() {
        guard let client = Self.steamClientURL else { return }
        NSWorkspace.shared.open([SteamPlayState.downloadsURL], withApplicationAt: client,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// The A hint for a Steam game, matching the Play pill; none while Play cannot do anything.
    func hint(for game: CatalogGame) -> [HintItem] {
        switch phase(of: game) {
        case .running: return [HintItem(.a, L10n.text("Resume"))]
        case .starting: return [HintItem(.a, L10n.text("Cancel"))]
        case .failed: return [HintItem(.a, L10n.text("Try again"))]
        case .idle:
            if isDownloading(game) { return Self.steamClientURL != nil ? [HintItem(.a, L10n.text("Steam downloads"))] : [] }
            return canPlay(game) ? [HintItem(.a, L10n.text("Play"))] : []
        }
    }

    /// The pill and A press: waiting cancels, anything else plays (or brings a running game forward).
    func press(_ game: CatalogGame) {
        // One launch at a time: the launch screen covers the library, and input reaching it changes nothing.
        guard !isLaunchScreenShowing() else { return }
        if case .idle = phase(of: game), isDownloading(game) { openDownloads(); return }
        if case .starting = phase(of: game) { cancel(game) } else { play(game) }
    }

    /// Steam is coming back for the player: the game is late and Steam may be asking for something.
    func mayNeedSteam(_ game: CatalogGame) -> Bool { late.contains(game.id) }

    func start(sessions: PlaySessionStore, settings: AppSettingsStore) {
        guard tokens.isEmpty else { return }
        self.sessions = sessions
        self.settings = settings
        watchingSince = Date()
        let center = NSWorkspace.shared.notificationCenter
        // Launches and quits arrive through the `runningApplications` observation below, once each.
        // Steam brings itself forward when it gets steam://run; during a background launch it goes away again.
        tokens = [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didUnhideApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier
                let isSteam = app?.bundleIdentifier == Self.steamBundleID
                Task { @MainActor in
                    // Steam may be coming forward to ask something: look in its log at once.
                    if isSteam { self?.lookForQuestion(); self?.followBackground() }
                    if name == NSWorkspace.didActivateApplicationNotification { self?.activated(pid: pid, isSteam: isSteam) }
                }
            }
        }
        listObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(heartbeat: true) }
        }
        refresh()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens { center.removeObserver(token) }
        tokens = []
        listObservation?.invalidate(); listObservation = nil
        timer?.invalidate(); timer = nil
        // A later start re-reads the processes: `RunningGameMonitor.start` closes open Steam sessions
        // at their last heartbeat, and a game still running must start a new one, not stay "running".
        states = [:]
        canonicalProcesses = [:]
        returnFocus = SteamReturnFocus()
        hideAgain?.cancel(); hideAgain = nil
        readiness?.cancel(); readiness = nil
        stopWatchingQuestions()
        // A screen still up leaves the usual way before the wait is forgotten.
        if launchScreen?.ready == false { launchScreen?.ready = true }
        launchScreen = nil
        patience = [:]
        sessions = nil
        settings = nil
        if backgrounds.values.contains(true) { Self.showSteam() }
        backgrounds = [:]
        late = []
    }

    /// The catalog changed. A game no longer in it keeps its session until its process ends.
    func setGames(_ all: [CatalogGame], sources: [CatalogSourceConfiguration]) {
        games = all.filter { $0.integration == .steam }
        steamEnabled = sources.contains { $0.integration == .steam && $0.isEnabled }
        steamRoot = sources.first { $0.integration == .steam && $0.isEnabled }?.rootURL
        refresh()
    }

    /// The registered handler of steam:// URLs, when it is Valve's Steam client.
    static var steamClientURL: URL? {
        guard let probe = URL(string: "steam://"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: probe),
              Bundle(url: handler)?.bundleIdentifier == steamBundleID else { return nil }
        return handler
    }

    func play(_ game: CatalogGame) {
        // A game that quit since the last notification is not resumed: read the processes first.
        refresh()
        let presentation = CatalogGamePresentation(game: game, sourceEnabled: steamEnabled)
        let client = Self.steamClientURL
        var state = states[game.id] ?? SteamPlayState()
        let request = state.requestPlay(target: presentation.launchTarget, clientAvailable: client != nil, now: Date())
        states[game.id] = state
        switch request {
        case .resume(let pid):
            if let app = NSRunningApplication(processIdentifier: pid) { RunningGameMonitor.activate(app) }
        case .handOff(let url, let generation):
            guard let client else { return }
            returnFocus.playPressed(game.id)
            hideAgain?.cancel(); hideAgain = nil
            // Steam gets the request in the background: NX Library stays in front until the game's
            // own window appears, instead of Steam's library flashing up in between.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            let id = game.id
            let background = settings?.settings.steamInBackground ?? false
            let steam = Self.steamApplication
            // Launch arguments reach only a Steam that this request starts.
            configuration.arguments = SteamBackgroundLaunch.arguments(enabled: background, steamRunning: steam != nil)
            late.remove(id)
            let wait = SteamBackgroundLaunch.patience(steamWasRunning: steam != nil)
            patience[id] = wait
            readiness?.cancel(); readiness = nil
            launchScreen = LaunchScreen(gameID: id)
            watchQuestions(for: game)
            Timer.scheduledTimer(withTimeInterval: wait + 0.5, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.followBackground() }
            }
            if background {
                backgrounds[id] = backgrounds[id] ?? (steam.map { !$0.isHidden } ?? false)
            }
            followBackground()
            NSWorkspace.shared.open([url], withApplicationAt: client, configuration: configuration) { [weak self] _, error in
                let accepted = error == nil
                Task { @MainActor in self?.finishHandOff(id, accepted: accepted, generation: generation) }
            }
        case .wait, .refuse:
            break
        }
    }

    /// Stop waiting, or dismiss a failure. A game already running is not touched.
    func cancel(_ game: CatalogGame) {
        guard var state = states[game.id] else { return }
        state.cancel(); states[game.id] = state
        if !isRunning(game) { returnFocus.playAbandoned(game.id) }
        followBackground()
    }

    private func finishHandOff(_ id: UUID, accepted: Bool, generation: Int) {
        guard var state = states[id] else { return }
        state.handoffFinished(accepted: accepted, generation: generation)
        states[id] = state
        refresh()
    }

    private func refresh(heartbeat: Bool = false) {
        // Before `start` there is no session store: a game seen now would turn "running" with no session.
        guard sessions != nil else { return }
        // The list drops an app when it quits (no `isTerminated` round trip to LaunchServices per app), and a pid's
        // paths are resolved once while it lives.
        var resolved: [Int32: NativeProcessObservation] = [:]
        let processes = NSWorkspace.shared.runningApplications.map { app -> NativeProcessObservation in
            let pid = app.processIdentifier
            let observed = NativeProcessObservation(pid: pid, bundleURL: app.bundleURL, executableURL: app.executableURL)
            let process = canonicalProcesses[pid].flatMap { $0.observed == observed ? $0.canonical : nil } ?? observed.canonical()
            canonicalProcesses[pid] = (observed, process)
            resolved[pid] = process
            return process
        }
        canonicalProcesses = canonicalProcesses.filter { resolved[$0.key] != nil }
        let now = Date()
        var next = states
        var ended: [UUID] = []
        let followed = Set(games.map(\.id)).union(states.keys)
        for id in followed {
            let game = games.first { $0.id == id }
            let app = game?.steamGame?.firstAvailableInstallation?.primaryApplication
            var state = next[id] ?? SteamPlayState()
            switch state.observe(processes, application: app, now: now) {
            case .started(let pid):
                if let appID = game?.steamGame?.appID {
                    // A game already running when NX Library began watching (a relaunch) keeps its Spotlight place.
                    let launched = NSRunningApplication(processIdentifier: pid)?.launchDate
                    let isNew = launched.map { $0 >= watchingSince } ?? true
                    sessions?.start(gameID: id, sourceID: "steam-\(appID)", announces: isNew)
                }
                // The game may have come forward before its process was seen.
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { returnFocus.gameCameForward(id) }
            case .ended:
                for session in sessions?.end(gameID: id) ?? [] {
                    guard let game, let sessions,
                          let summary = SessionSummary(session: session, game: game,
                                                       total: sessions.totalDuration(for: id)) else { continue }
                    endedSession = summary
                }
                ended.append(id)
            case nil:
                if heartbeat, case .running = state.phase { sessions?.heartbeat(for: id) }
            }
            if case .failed = state.phase { returnFocus.playAbandoned(id) }
            if state.phase == .idle, game == nil { next[id] = nil } else { next[id] = state }
        }
        if next != states { states = next }
        // Quits are judged once every game's state is known, so two games quitting together see each other gone.
        if !ended.isEmpty {
            SteamPlaytimeCoordinator.shared.sessionEnded()
            SteamAchievementsStore.shared.sessionEnded()
        }
        for id in ended { gameEnded(id) }
        followBackground()
    }

    // MARK: - Back to NX Library

    /// NX Library comes back for a game played from it that was in front with no other library game open. A Steam
    /// that was out of view before Play goes back out of view, unless the player had left the game (for Steam
    /// itself, say).
    private func gameEnded(_ id: UUID) {
        let othersRunning = nativeGames?.runningGameIDs.isEmpty == false || hasRunningGame
        let ending = returnFocus.gameEnded(id, othersRunning: othersRunning)
        if ending.returnsToLibrary { comeBack() }
        if ending.wasInFront, settings?.settings.steamInBackground == true, backgrounds[id] == false { hideSteamAgain() }
    }

    /// A Steam game came to the front, or another app stayed in front a second later while it ran: the player left
    /// the game (an app macOS brings forward as a game quits does not count). Steam coming forward while the launch
    /// screen waits is left alone: the screen's own window stays over it.
    private func activated(pid: Int32?, isSteam: Bool) {
        if let pid, let id = states.first(where: { $0.value.phase == .running(pid: pid) })?.key {
            returnFocus.gameCameForward(id)
            return
        }
        guard let game = returnFocus.gameInFront, case .running(let gamePID) = phase(ofID: game) else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, self.phase(ofID: game) == .running(pid: gamePID),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier != gamePID else { return }
            self.returnFocus.otherAppStayedForward(whileRunning: game)
        }
    }

    private func phase(ofID id: UUID) -> SteamPlayState.Phase { states[id]?.phase ?? .idle }

    private func comeBack() {
        LibraryWindow.comeForward { [weak self] app in
            guard let self else { return false }
            return self.isRunningGame(pid: app.processIdentifier) || self.nativeGames?.isLibraryGame(app) == true
        }
    }

    // MARK: - Keep Steam in the background

    private static var steamApplication: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: steamBundleID).first { !$0.isTerminated }
    }

    /// A Steam that was out of view before Play goes back out of view once the game quits: now, and once more
    /// when Steam shows its own window a moment later. Steam putting itself in front as the game quits is Steam's
    /// doing, not the player's, so it is hidden even then. A new Play or `stop` cancels the second look.
    private func hideSteamAgain() {
        let hide = {
            guard let steam = Self.steamApplication, !steam.isHidden else { return }
            steam.hide()
        }
        hide()
        hideAgain?.cancel()
        hideAgain = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    private static func showSteam() {
        // Shown, not brought forward: NX Library or the game keeps the focus.
        if let steam = steamApplication, steam.isHidden { steam.unhide() }
    }

    // MARK: - Launch screen

    /// The launch screen for `gameID` closed (it faded, the player dismissed it, or it never showed). One the player
    /// dismissed while the game was still on its way may have covered a Space change to Steam: NX Library comes
    /// forward, unless a game is in front. Applied after the current publish: a value set while `launchScreen` is
    /// being published is overwritten by it.
    func launchScreenClosed(_ gameID: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let screen = self.launchScreen, screen.gameID == gameID else { return }
            self.launchScreen = nil
            self.readiness?.cancel(); self.readiness = nil
            if !screen.ready, !NSApp.isActive || NSApp.mainWindow?.isOnActiveSpace == false { self.comeBack() }
        }
    }

    /// Reads Steam's log for a question about `game`'s launch for as long as it is on its way, launch screen or not.
    private func watchQuestions(for game: CatalogGame) {
        stopWatchingQuestions()
        guard let appID = game.steamGame?.appID, let steamRoot else { return }
        questionWatch = (game.id, SteamLaunchQuestionWatch(appID: appID, steamRoot: steamRoot))
        questionTimer = Timer.scheduledTimer(withTimeInterval: Self.questionLook, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.lookForQuestion() }
        }
        lookForQuestion()
    }

    private func stopWatchingQuestions() {
        questionTimer?.invalidate(); questionTimer = nil
        questionWatch = nil
        questionGeneration += 1
    }

    /// Reads Steam's log off the main thread (the first look takes up to a megabyte).
    private func lookForQuestion() {
        guard let watching = questionWatch else { return }
        guard case .starting = phase(ofID: watching.gameID) else { return stopWatchingQuestions() }
        guard !questionLooking else { return }
        questionLooking = true
        let generation = questionGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            var watch = watching.watch
            let asks = watch.look(now: Date())
            await self?.looked(watch, asks: asks, generation: generation)
        }
    }

    /// Steam waits on the player for the game on its way: Steam is handed the wait at once.
    private func looked(_ watch: SteamLaunchQuestionWatch, asks: Bool, generation: Int) {
        questionLooking = false
        guard generation == questionGeneration, let gameID = questionWatch?.gameID else { return }
        questionWatch = (gameID, watch)
        guard asks, case .starting = phase(ofID: gameID) else { return }
        stopWatchingQuestions()
        handToSteam(gameID)
    }

    /// Steam may need the player for this wait: it stops being kept away, is shown, and the head says to check it.
    /// While the game's launch screen waits, Steam is also brought forward and the screen leaves; a player who
    /// dismissed the screen is left where they are.
    private func handToSteam(_ id: UUID) {
        late.insert(id)
        backgrounds[id] = nil
        Self.showSteam()
        guard var screen = launchScreen, screen.gameID == id, !screen.ready else { return }
        if let steam = Self.steamApplication { RunningGameMonitor.activate(steam) }
        screen.ready = true
        launchScreen = screen
    }

    /// Moves the launch screen on: the game started (it leaves once the window is up), Steam is late (Steam is
    /// shown and, while the player waits in NX Library, brought forward) or Play ended.
    private func followLaunchScreen(now: Date) {
        guard var screen = launchScreen, !screen.ready else { return }
        let id = screen.gameID
        let phase = phase(ofID: id)
        switch SteamBackgroundLaunch.launchScreen(phase: phase, now: now,
                                                  patience: patience[id] ?? SteamBackgroundLaunch.attentionDelay) {
        case .waiting:
            return
        case .gameStarted:
            if case .running(let pid) = phase { watchWindow(of: id, pid: pid) }
            return
        case .late:
            handToSteam(id)
            return
        case .over:
            break
        }
        screen.ready = true
        launchScreen = screen
    }

    /// Once the started game's window is on screen, the game comes forward and the launch screen leaves; after
    /// 60 s without a window the screen leaves anyway, as for an nxnative game.
    private func watchWindow(of id: UUID, pid: Int32) {
        guard readiness == nil else { return }
        // Every process of the game's app counts, as for an nxnative game: its window may belong to another one.
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        readiness = Task { @MainActor [weak self] in
            let visible = if let bundleID {
                await LaunchReadinessProbe().waitUntilVisible(bundleID: bundleID)
            } else {
                await LaunchReadinessProbe().waitUntilVisible(pid: pid)
            }
            guard !Task.isCancelled, let self, self.launchScreen?.gameID == id else { return }
            if visible {
                SoundEffectService.shared.play(.gameReady)
                if let app = NSRunningApplication(processIdentifier: pid) { RunningGameMonitor.activate(app) }
            }
            self.launchScreen?.ready = true
            self.readiness = nil
        }
    }

    /// Hides Steam while a background launch is on its way; shows it again when the game is late,
    /// and once Play is over if it was in view before.
    private func followBackground(now: Date = Date()) {
        var keepAway = false
        for (id, wasVisible) in backgrounds {
            let phase = states[id]?.phase ?? .idle
            switch phase {
            case .starting:
                let wait = patience[id] ?? SteamBackgroundLaunch.attentionDelay
                if SteamBackgroundLaunch.mayNeedPlayer(phase: phase, now: now, patience: wait) {
                    backgrounds[id] = nil
                    late.insert(id)
                    Self.showSteam()
                } else if SteamBackgroundLaunch.keepsSteamAway(phase: phase, now: now, patience: wait) {
                    keepAway = true
                }
            case .running:
                break
            case .idle, .failed:
                backgrounds[id] = nil
                if wasVisible { Self.showSteam() }
            }
        }
        let waiting = Set(states.compactMap { id, state -> UUID? in
            if case .starting = state.phase { return id } else { return nil }
        })
        // Any wait Play started here is late past its patience, whether or not Steam is kept in the background or
        // the launch screen is still up: the head then says to check Steam.
        for (id, wait) in patience
        where SteamBackgroundLaunch.mayNeedPlayer(phase: phase(ofID: id), now: now, patience: wait) {
            late.insert(id)
        }
        if !late.isSubset(of: waiting) { late.formIntersection(waiting) }
        patience = patience.filter { waiting.contains($0.key) || launchScreen?.gameID == $0.key }
        if keepAway, let steam = Self.steamApplication, !steam.isHidden { steam.hide() }
        followLaunchScreen(now: now)
    }
}
