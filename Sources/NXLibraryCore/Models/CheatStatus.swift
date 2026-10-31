import Foundation

/// Whether a game's installed app can use cheats, and the short words the UI shows for them.
public enum CheatStatus: Equatable, Sendable {
    /// The nxnative commit that brought host cheats (PR #406); an app built with an engine without it has none.
    public static let cheatsCommit = "ef9f9bbaff5801dbd039bd10d4f2a9158edbae14"

    /// The reason, for the Cheats panel.
    case needsRebuild(String)
    case ready

    /// `isAncestor(commit)` answers whether `commit` contains `cheatsCommit`; nil when it cannot tell.
    public static func of(engineCommit: String?, buildID: String?, titleID: String?,
                          isAncestor: (String) -> Bool?) -> CheatStatus {
        guard titleID != nil else { return .needsRebuild("Cheats need the game's title ID, which this app does not carry.") }
        guard let engineCommit, isAncestor(engineCommit) == true else {
            return .needsRebuild("This app was built with an engine without cheats.")
        }
        guard buildID != nil else { return .needsRebuild("This app does not say which version of the game it is.") }
        return .ready
    }

    /// The Game Options row's value: "Rebuild", "None", "Off" or "N on".
    public static func rowValue(_ status: CheatStatus, state: CheatState?) -> String {
        guard status == .ready else { return "Rebuild" }
        guard let state, state.file != nil else { return "None" }
        return state.masterOn ? "\(state.onCount) on" : "Off"
    }

    /// The detail page's "Cheats on": the master switch on and at least one switch on (masters alone do not count).
    public static func showsDetailLabel(_ status: CheatStatus, state: CheatState?) -> Bool {
        guard status == .ready, let state else { return false }
        return state.masterOn && state.onCount > 0
    }
}

/// Whether an engine commit contains another, from the engine checkout (`git merge-base --is-ancestor`), cached per
/// commit: build records name the commit an app was built with.
public final class EngineAncestry {
    private let runner: CommandRunning
    private let engineFolder: URL
    private var cache: [String: Bool?] = [:]

    public init(runner: CommandRunning, engineFolder: URL) {
        self.runner = runner
        self.engineFolder = engineFolder
    }

    /// True when `commit` contains `ancestor`, false when it does not, nil when git cannot tell (unknown commit, no
    /// checkout).
    public func contains(_ ancestor: String, in commit: String) -> Bool? {
        let key = ancestor + " " + commit
        if let known = cache[key] { return known }
        let result = try? runner.run(URL(fileURLWithPath: "/usr/bin/git"),
                                     ["-C", engineFolder.path, "merge-base", "--is-ancestor", ancestor, commit],
                                     environment: nil, currentDirectory: nil)
        let answer: Bool? = switch result?.status {
        case 0: true
        case 1: false
        default: nil
        }
        cache[key] = answer
        return answer
    }
}
