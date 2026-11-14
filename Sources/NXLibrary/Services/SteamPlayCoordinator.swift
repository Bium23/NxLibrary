import AppKit
import Combine
import NXLibraryCore

/// Play for Steam games and their real sessions (`SteamPlayState`). Play sends `steam://run/<AppID>`
/// to the registered Steam client only; it never opens the game's app itself. The process list is
/// read on launches, quits and the app list changing, and every 30 s for waits and heartbeats: the
/// installation's own app starts a session, its exit ends it, Steam staying open does not count.
/// The catalog is not written here; only `PlaySessionStore` is.
///
/// With "Keep Steam in the background" (`SteamBackgroundLaunch`), a Steam that Play starts opens
/// with `-silent -nofriendsui`, and an open Steam is hidden while the game is on its way. Past
/// `attentionDelay` Steam is shown again and the head says to check it; once Play is over,
/// Steam comes back only if it was in view before.
@MainActor
final class SteamPlayCoordinator: ObservableObject {
    static let shared = SteamPlayCoordinator()
    static let steamBundleID = "com.valvesoftware.steam"
    private static let tick: TimeInterval = 30

    @Published private(set) var states: [UUID: SteamPlayState] = [:]
    /// Waits past `attentionDelay` of a background launch: Steam is back in view and may need the player.
    @Published private(set) var late: Set<UUID> = []

    private var games: [CatalogGame] = []
    private var steamEnabled = false
    private var sessions: PlaySessionStore?
    private var settings: AppSettingsStore?
    /// Background launches in progress, with whether Steam was in view before Play.
    private var backgrounds: [UUID: Bool] = [:]
    private var tokens: [NSObjectProtocol] = []
    private var listObservation: NSKeyValueObservation?
    private var timer: Timer?

    func phase(of game: CatalogGame) -> SteamPlayState.Phase { states[game.id]?.phase ?? .idle }
    func isRunning(_ game: CatalogGame) -> Bool { if case .running = phase(of: game) { return true }; return false }
    /// One available, recognized installation in an enabled source: what Play needs.
    func canPlay(_ game: CatalogGame) -> Bool {
        CatalogGamePresentation(game: game, sourceEnabled: steamEnabled).launchTarget != nil
    }

    /// The A hint for a Steam game, matching the Play pill; none while Play cannot do anything.
    func hint(for game: CatalogGame) -> [HintItem] {
        switch phase(of: game) {
        case .running: return [HintItem(.a, L10n.text("Resume"))]
        case .starting: return [HintItem(.a, L10n.text("Cancel"))]
        case .failed: return [HintItem(.a, L10n.text("Try again"))]
        case .idle: return canPlay(game) ? [HintItem(.a, L10n.text("Play"))] : []
        }
    }

    /// The pill and A press: waiting cancels, anything else plays (or brings a running game forward).
    func press(_ game: CatalogGame) {
        if case .starting = phase(of: game) { cancel(game) } else { play(game) }
    }

    /// Steam is coming back for the player: the game is late and Steam may be asking for something.
    func mayNeedSteam(_ game: CatalogGame) -> Bool { late.contains(game.id) }

    func start(sessions: PlaySessionStore, settings: AppSettingsStore) {
        guard tokens.isEmpty else { return }
        self.sessions = sessions
        self.settings = settings
        let center = NSWorkspace.shared.notificationCenter
        tokens = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map {
            center.addObserver(forName: $0, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        // Steam brings itself forward when it gets steam://run; during a background launch it goes away again.
        tokens += [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didUnhideApplicationNotification].map {
            center.addObserver(forName: $0, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.steamBundleID else { return }
                Task { @MainActor in self?.followBackground() }
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
            if background {
                backgrounds[id] = backgrounds[id] ?? (steam.map { !$0.isHidden } ?? false)
                Timer.scheduledTimer(withTimeInterval: SteamBackgroundLaunch.attentionDelay + 0.5, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.followBackground() }
                }
                followBackground()
            }
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
        let processes = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.map {
            NativeProcessObservation(pid: $0.processIdentifier, bundleURL: $0.bundleURL, executableURL: $0.executableURL)
        }
        let now = Date()
        var next = states
        let followed = Set(games.map(\.id)).union(states.keys)
        for id in followed {
            let game = games.first { $0.id == id }
            let app = game?.steamGame?.installations.first { $0.availability == .available }?.primaryApplication
            var state = next[id] ?? SteamPlayState()
            switch state.observe(processes, application: app, now: now) {
            case .started:
                if let appID = game?.steamGame?.appID { sessions?.start(gameID: id, sourceID: "steam-\(appID)") }
            case .ended:
                sessions?.end(gameID: id)
            case nil:
                if heartbeat, case .running = state.phase { sessions?.heartbeat(for: id) }
            }
            if state.phase == .idle, game == nil { next[id] = nil } else { next[id] = state }
        }
        if next != states { states = next }
        followBackground()
    }

    // MARK: - Keep Steam in the background

    private static var steamApplication: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: steamBundleID).first { !$0.isTerminated }
    }

    private static func showSteam() {
        // Shown, not brought forward: NX Library or the game keeps the focus.
        if let steam = steamApplication, steam.isHidden { steam.unhide() }
    }

    /// Hides Steam while a background launch is on its way; shows it again when the game is late,
    /// and once Play is over if it was in view before.
    private func followBackground(now: Date = Date()) {
        var keepAway = false
        for (id, wasVisible) in backgrounds {
            let phase = states[id]?.phase ?? .idle
            switch phase {
            case .starting:
                if SteamBackgroundLaunch.mayNeedPlayer(enabled: true, phase: phase, now: now) {
                    backgrounds[id] = nil
                    late.insert(id)
                    Self.showSteam()
                } else if SteamBackgroundLaunch.keepsSteamAway(enabled: true, phase: phase, now: now) {
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
        if !late.isSubset(of: waiting) { late.formIntersection(waiting) }
        if keepAway, let steam = Self.steamApplication, !steam.isHidden { steam.hide() }
    }
}
