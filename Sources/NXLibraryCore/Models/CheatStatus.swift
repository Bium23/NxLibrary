import Foundation
import os

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
/// commit: build records name the commit an app was built with. Git runs only in `answer`, off the caller's thread,
/// because the Cheats row and panel open inside a SwiftUI update; views read `keptAnswer`, which never runs it.
public final class EngineAncestry: Sendable {
    private let runner: any CommandRunning & Sendable
    private let engineFolder: URL
    private let cache = OSAllocatedUnfairLock<[String: Bool?]>(initialState: [:])

    public init(runner: any CommandRunning & Sendable, engineFolder: URL) {
        self.runner = runner
        self.engineFolder = engineFolder
    }

    /// The answer kept from an earlier `answer`, without running git: nil when this pair was not asked yet,
    /// `.some(nil)` when git could not tell.
    public func keptAnswer(_ ancestor: String, in commit: String) -> Bool?? {
        let key = Self.key(ancestor, commit)
        return cache.withLock { $0[key] }
    }

    /// True when `commit` contains `ancestor`, false when it does not, nil when git cannot tell (unknown commit, no
    /// checkout). Git runs in a detached task, once per pair; the answer is kept for `keptAnswer`.
    public func answer(_ ancestor: String, in commit: String) async -> Bool? {
        if let known = keptAnswer(ancestor, in: commit) { return known }
        let answer = await Task.detached { [runner, engineFolder] in
            let result = try? runner.run(URL(fileURLWithPath: "/usr/bin/git"),
                                         ["-C", engineFolder.path, "merge-base", "--is-ancestor", ancestor, commit],
                                         environment: nil, currentDirectory: nil)
            let answer: Bool? = switch result?.status {
            case 0: true
            case 1: false
            default: nil
            }
            return answer
        }.value
        let key = Self.key(ancestor, commit)
        cache.withLock { $0[key] = .some(answer) }
        return answer
    }

    private static func key(_ ancestor: String, _ commit: String) -> String { ancestor + " " + commit }
}
