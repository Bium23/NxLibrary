import Foundation

/// The player's choice to build with nxnative main before NX Library has tested it (Settings → Engine,
/// Newest engine). NX Library never follows main by itself: the choice is explicit, turns the untested-toolchain
/// override on, and records every build it makes as untested.
public struct NewestEngineChoice: Codable, Equatable, Sendable {
    /// The commit the engine was switched to.
    public var commit: String
    /// How many commits it was ahead of the tested pin when chosen.
    public var aheadBy: Int
    /// The override was off and the choice turned it on, so going back turns it off again.
    public var turnedOnOverride: Bool

    public init(commit: String, aheadBy: Int, turnedOnOverride: Bool) {
        self.commit = commit
        self.aheadBy = aheadBy
        self.turnedOnOverride = turnedOnOverride
    }

    public var shortCommit: String { String(commit.prefix(7)) }
}

/// Whether the newest nxnative can be used by this NX Library.
public enum NewestEngineReadiness: Equatable, Sendable {
    /// Same certified Metal compiler as the tested engine.
    case usable
    /// main certifies another Metal compiler: Setup cannot provide it, so it waits for an NX Library update.
    case needsNewerApp(metal: String)
    /// The lock could not be read yet; the switch reads it again before changing anything.
    case unknown
}

/// A button on Settings → Engine's Newest engine row.
public enum NewestEngineAction: Equatable, Sendable {
    case useNewest, update, backToTested
}

/// A tag beside an upstream commit while the newest engine is in use.
public enum UpstreamCommitMark: Equatable, Sendable {
    case inUse, new
}

/// The words every screen uses for the newest engine, so Settings and Setup say the same thing.
public enum NewestEngineCopy {
    public static let note = "Newest nxnative, not yet tested by NX Library. It usually works, but something may not. "
        + "Its new features reach NX Library in a future version."

    public static func ahead(_ count: Int) -> String {
        "\(count) commit\(count == 1 ? "" : "s") ahead"
    }

    /// Settings → Engine, Newest engine row, while the tested engine is in use.
    public static func offer(commit: String, aheadBy: Int) -> String {
        "Build with nxnative main (\(commit.prefix(7)), \(ahead(aheadBy))) before NX Library has tested it."
    }

    public static func needsNewerApp(metal: String) -> String {
        "The newest nxnative needs Metal \(metal), so it needs a newer NX Library."
    }

    /// Setup's engine card while the newest engine is in use (the note is its description).
    public static func setupDetail(choice: NewestEngineChoice, tested: String) -> String {
        "At \(choice.shortCommit), \(ahead(choice.aheadBy)) of the tested \(tested.prefix(7)), chosen in Settings → Engine."
    }

    /// Settings → Engine, Newest engine row, while main is past the commit in use. `aheadBy` counts from the pin,
    /// like the choice's own count; a rewritten main (not further ahead) gets no count.
    public static func update(choice: NewestEngineChoice, main: String, aheadBy: Int) -> String {
        let newer = aheadBy - choice.aheadBy
        let count = newer > 0 ? ", \(newer) commit\(newer == 1 ? "" : "s") newer" : ""
        return "main has moved on: \(main.prefix(7))\(count)."
    }

    public static let info = "Builds games with nxnative main instead of the engine this NX Library is tested with. "
        + "Builds are recorded as untested and the untested-toolchain override stays on. "
        + "Back to tested returns to the tested engine; games you built keep playing."
}

public enum NewestEngineError: Error, Equatable, LocalizedError {
    case localChanges
    case downloadFailed
    case needsNewerApp(metal: String)
    case switchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .localChanges:
            return "The engine folder has changed files. NX Library never touches them: put them aside, then try again."
        case .downloadFailed:
            return "The newest nxnative could not be downloaded. Check the connection, then try again."
        case .needsNewerApp(let metal):
            return NewestEngineCopy.needsNewerApp(metal: metal)
        case .switchFailed(let detail):
            return "The engine could not be switched: \(detail)"
        }
    }
}

public enum NewestEngine {
    static let lockPath = "dm/gfx/tools/dmsh_chain.lock"

    /// The Metal compiler a `dmsh_chain.lock` certifies for the Mac ("32023.922"); nil when it names none.
    public static func lockMetal(_ lock: String) -> String? {
        lock.split(separator: "\n").first { $0.hasPrefix("metal_macosx\t") }
            .flatMap { CompatibilityChecker.metalNumber(String($0.dropFirst("metal_macosx\t".count))) }
    }

    /// Usable only when main certifies the same Metal compiler as the tested engine: a different compiler is a
    /// Setup change this NX Library cannot make. Xcode follows the compiler.
    public static func readiness(newestLock: String?, testedMetal: String?) -> NewestEngineReadiness {
        guard let newestLock, let metal = lockMetal(newestLock),
              let tested = testedMetal.flatMap(CompatibilityChecker.metalNumber) else { return .unknown }
        return metal == tested ? .usable : .needsNewerApp(metal: metal)
    }

    /// The lock of an upstream commit, read before any switch so the row can say it in advance.
    public static func lockURL(commit: String) -> URL? {
        guard !commit.isEmpty, commit.allSatisfy(\.isHexDigit) else { return nil }
        return URL(string: "https://raw.githubusercontent.com/\(UpstreamChecker.repository)/\(commit)/\(lockPath)")
    }

    public static func fetchLock(commit: String,
                                 client: UpstreamHTTPClient = URLSessionUpstreamClient()) async -> String? {
        guard let url = lockURL(commit: commit) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("NXLibrary/0.1", forHTTPHeaderField: "User-Agent")
        guard let (data, http) = try? await client.data(for: request), (200..<300).contains(http.statusCode) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// The Newest engine row's buttons. `main`: upstream main when it is ahead of the pin (nil when it is the pin or
    /// was not checked). Update moves an existing choice to a newer main; a main that needs another Metal compiler
    /// offers neither Use newest nor Update. Unknown readiness still offers them: the switch reads the lock first.
    public static func actions(choice: NewestEngineChoice?, main: String?,
                               readiness: NewestEngineReadiness?) -> [NewestEngineAction] {
        var blocked = false
        if case .needsNewerApp = readiness { blocked = true }
        let movable = main != nil && main != choice?.commit && !blocked
        guard choice != nil else { return movable ? [.useNewest] : [] }
        return movable ? [.update, .backToTested] : [.backToTested]
    }

    /// The row's buttons on a controller: A takes the first (Update when main moved on, else Use newest or Back to
    /// tested), Y the second (Back to tested beside Update). Nil when the row has no button.
    public static func controller(_ actions: [NewestEngineAction])
        -> (primary: NewestEngineAction, secondary: NewestEngineAction?)? {
        guard let primary = actions.first else { return nil }
        return (primary, actions.dropFirst().first)
    }

    /// Tags for Settings → Engine's upstream list (newest first): the commit the newest engine is at is In use,
    /// those above it New. Nothing on the tested engine, or when the commit in use is not in the list.
    public static func marks(_ commits: [UpstreamCommit], inUse: String?) -> [String: UpstreamCommitMark] {
        guard let inUse, let index = commits.firstIndex(where: { $0.sha == inUse }) else { return [:] }
        var marks: [String: UpstreamCommitMark] = [inUse: .inUse]
        for commit in commits[..<index] { marks[commit.sha] = .new }
        return marks
    }

    /// A choice holds while the checkout is still at its commit and the tested pin has not caught up with it.
    /// `includedInPin`: the commit is an ancestor of the pin (an NX Library update tested it); nil when unknown.
    public static func keeps(_ choice: NewestEngineChoice, head: String?, pinned: String, includedInPin: Bool?) -> Bool {
        guard let head, head == choice.commit, choice.commit != pinned else { return false }
        return includedInPin != true
    }
}

/// Moves the engine checkout between the tested pin and main with git, never touching changed files.
public struct NewestEngineSwitcher {
    private let repo: URL
    private let runner: CommandRunning
    private let environment: [String: String]?

    public init(repo: URL, runner: CommandRunning = SystemCommandRunner(), environment: [String: String]? = nil) {
        self.repo = repo
        self.runner = runner
        self.environment = environment
    }

    private func git(_ args: [String]) -> CommandResult {
        (try? runner.run(URL(fileURLWithPath: "/usr/bin/git"), ["-C", repo.path] + args,
                         environment: environment, currentDirectory: nil))
            ?? CommandResult(status: -1, stdout: "", stderr: "git could not run")
    }

    private func requireClean() throws {
        let status = git(["status", "--porcelain"])
        guard status.status == 0 else { throw NewestEngineError.switchFailed(Self.firstLine(status.stderr)) }
        guard CompatibilityChecker.relevantChanges(status.stdout).isEmpty else { throw NewestEngineError.localChanges }
    }

    /// Downloads `commit`, reads its lock and switches to it only when it certifies `testedMetal`.
    public func useNewest(commit: String, testedMetal: String?) throws {
        try requireClean()
        guard git(["fetch", "--quiet", "origin"]).status == 0 else { throw NewestEngineError.downloadFailed }
        let lock = git(["show", "\(commit):\(NewestEngine.lockPath)"])
        guard lock.status == 0 else { throw NewestEngineError.downloadFailed }
        if case .needsNewerApp(let metal) = NewestEngine.readiness(newestLock: lock.stdout, testedMetal: testedMetal) {
            throw NewestEngineError.needsNewerApp(metal: metal)
        }
        try checkout(commit)
    }

    /// Returns to the tested pin, downloading it first if the checkout does not have it.
    public func useTested(pinned: String) throws {
        try requireClean()
        if git(["cat-file", "-e", "\(pinned)^{commit}"]).status != 0,
           git(["fetch", "--quiet", "origin"]).status != 0 {
            throw NewestEngineError.downloadFailed
        }
        try checkout(pinned)
    }

    /// The Metal compiler `commit`'s lock certifies, read from git (the checkout may be at another commit).
    public func lockMetal(at commit: String) -> String? {
        let lock = git(["show", "\(commit):\(NewestEngine.lockPath)"])
        return lock.status == 0 ? NewestEngine.lockMetal(lock.stdout) : nil
    }

    /// Whether `commit` is an ancestor of (or equal to) `pinned`; nil when git cannot tell.
    public func isIncluded(_ commit: String, in pinned: String) -> Bool? {
        switch git(["merge-base", "--is-ancestor", commit, pinned]).status {
        case 0: return true
        case 1: return false
        default: return nil
        }
    }

    private func checkout(_ commit: String) throws {
        let result = git(["checkout", "--quiet", "--detach", commit])
        guard result.status == 0 else { throw NewestEngineError.switchFailed(Self.firstLine(result.stderr)) }
    }

    static func firstLine(_ text: String) -> String {
        text.split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "unknown error"
    }
}
