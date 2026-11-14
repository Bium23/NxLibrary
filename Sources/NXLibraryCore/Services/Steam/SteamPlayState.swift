import Foundation

/// One live process as the system reports it, reduced to what identifies an installed app.
public struct NativeProcessObservation: Equatable, Sendable {
    public let pid: Int32
    public let bundleURL: URL?
    public let executableURL: URL?
    public init(pid: Int32, bundleURL: URL?, executableURL: URL?) {
        self.pid = pid; self.bundleURL = bundleURL; self.executableURL = executableURL
    }
}

public enum SteamPlayFailure: Equatable, Sendable {
    /// No single available, recognized installation in an enabled source.
    case unavailable
    /// No Steam client registered on this Mac.
    case clientMissing
    /// The system did not hand the request to Steam.
    case handoffRejected
    /// Steam took the request but the game's own app never appeared in time.
    case notStarted
}

/// A Steam game's Play and its real session, as pure state. Handing the request to Steam
/// starts nothing: the session starts when the installation's own app is seen running and
/// ends when that process goes, whatever Steam itself does. A game started from Steam
/// directly is followed the same way. Requests carry a generation, so a late answer to an
/// older Play never changes a newer one.
public struct SteamPlayState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Waiting for the game's app; `accepted` once the system handed the request to Steam.
        case starting(since: Date, accepted: Bool)
        case running(pid: Int32)
        case failed(SteamPlayFailure)
    }

    public enum Request: Equatable, Sendable {
        case handOff(URL, generation: Int)
        case resume(pid: Int32)
        /// Play pressed again while the first request is still on its way: nothing new is sent.
        case wait
        case refuse(SteamPlayFailure)
    }

    public enum Change: Equatable, Sendable {
        case started(pid: Int32)
        case ended(pid: Int32)
    }

    /// Steam may install an update or show its own window before the game starts.
    public static let startDeadline: TimeInterval = 300

    public private(set) var phase: Phase = .idle
    public private(set) var generation = 0
    /// The app the running session saw start: it lasts while that process lives, whatever the catalog
    /// says about the installation since (removed in a refresh, or now named at another path).
    private var runningBundle: URL?

    public init() {}

    /// The only URL NX Library sends: built from a validated numeric AppID, nothing else.
    public static func launchURL(appID: UInt32) -> URL? {
        appID > 0 ? URL(string: "steam://run/\(appID)") : nil
    }

    public mutating func requestPlay(target: CatalogLaunchTarget?, clientAvailable: Bool, now: Date) -> Request {
        switch phase {
        case .running(let pid): return .resume(pid: pid)
        case .starting: return .wait
        case .idle, .failed: break
        }
        guard case .steam(let appID)? = target, let url = Self.launchURL(appID: appID) else {
            phase = .failed(.unavailable); return .refuse(.unavailable)
        }
        guard clientAvailable else { phase = .failed(.clientMissing); return .refuse(.clientMissing) }
        generation += 1
        phase = .starting(since: now, accepted: false)
        return .handOff(url, generation: generation)
    }

    /// The system's answer to the hand-off. Only the current request's answer counts.
    public mutating func handoffFinished(accepted: Bool, generation: Int) {
        guard generation == self.generation, case .starting(let since, _) = phase else { return }
        phase = accepted ? .starting(since: since, accepted: true) : .failed(.handoffRejected)
    }

    /// The player gave up waiting, or dismissed a failure.
    public mutating func cancel() {
        switch phase {
        case .starting, .failed: phase = .idle; generation += 1
        case .idle, .running: break
        }
    }

    /// Reads the process list. A running session ends when its process is gone; otherwise the
    /// installation's own app, once seen, starts one. Waiting too long fails without a session.
    public mutating func observe(_ processes: [NativeProcessObservation], application: CatalogNativeApplication?,
                                 now: Date) -> Change? {
        if case .running(let pid) = phase {
            // Same pid and still the app it started as: a pid the system reused for another program is not the game.
            if processes.contains(where: { process in
                process.pid == pid && (runningBundle.map { bundle in process.bundleURL.map { Self.same($0, bundle) } ?? false } ?? true)
            }) { return nil }
            phase = .idle
            runningBundle = nil
            return .ended(pid: pid)
        }
        if let application, let match = processes.first(where: { Self.matches($0, application) }) {
            phase = .running(pid: match.pid)
            runningBundle = match.bundleURL
            return .started(pid: match.pid)
        }
        if case .starting(let since, _) = phase, now.timeIntervalSince(since) > Self.startDeadline {
            phase = .failed(.notStarted)
        }
        return nil
    }

    /// The process is this installation's app: the same bundle, and its executable when the
    /// system names one. Steam itself, helpers and another copy of the game never match.
    public static func matches(_ process: NativeProcessObservation, _ application: CatalogNativeApplication) -> Bool {
        guard let bundle = process.bundleURL, same(bundle, application.url) else { return false }
        guard let executable = process.executableURL else { return true }
        return same(executable, application.executableURL)
    }

    static func same(_ a: URL, _ b: URL) -> Bool {
        a.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
