import Foundation

/// The Cheats panel's words (spec: Installing, Where it shows), kept here so they are tested.
public enum CheatCopy {
    /// Under the header: what a cheat is, against a mod. Players look for cheats among GameBanana's mods, where the
    /// cheat-like ones (unbreakable weapons, more items) are file mods and belong in Mods.
    public static let about =
        "Cheats change values while you play, for this version only. New items, looks or gameplay are in Mods."

    /// "Version 1.2.0 · build B424BE15…": the build ID cut to its first 8 hex digits.
    public static func header(version: String?, buildID: String?) -> String {
        let build = buildID.map { "build \($0.prefix(8))…" }
        switch (version, build) {
        case let (version?, build?): return "Version \(version) · \(build)"
        case let (version?, nil): return "Version \(version)"
        case let (nil, build?): return build.prefix(1).uppercased() + build.dropFirst()
        case (nil, nil): return ""
        }
    }

    /// One sentence for a file that is not installed; nil for one that can be.
    public static func refusal(_ decision: CheatInstall.Decision, gameName: String, buildID: String) -> String? {
        switch decision {
        case .install, .confirmUnnamed: return nil
        case .otherBuild(let other):
            return "These cheats are for another version of \(gameName) (build \(other)). Yours is build \(buildID)."
        case .otherTitle(let other): return "These cheats are for another game (title ID \(other))."
        case .refused(let reason): return reason
        }
    }

    public static let several = "Several files could be these cheats: add the one you want."
    public static let noFile = "There is no cheat file (.txt) there."

    /// The confirmation before every install: the parser's summary, the warning for a file whose name says no build,
    /// and what replacing keeps.
    public static func confirm(file: CheatFile, unnamed: Bool, replacing: Bool, version: String?,
                               buildID: String) -> (title: String, message: String, confirm: String) {
        var parts: [String] = []
        if unnamed {
            let target = version.map { "version \($0) (build \(buildID))" } ?? "build \(buildID)"
            parts.append("Install as cheats for \(target)? Cheats made for another version can crash the game.")
        }
        parts.append(file.summaryText)
        parts.append(replacing ? "Cheats that were on and keep their name stay on; the rest start off."
                               : "Every cheat starts off.")
        let title = replacing ? "Replace cheats?" : unnamed ? "Install these cheats?" : "Install cheats?"
        return (title, parts.joined(separator: "\n\n"), replacing ? "Replace" : "Install")
    }

    public static func removal(build: String) -> (title: String, message: String, confirm: String) {
        ("Remove cheats?", "The cheat files for build \(build) go to the Trash.", "Remove")
    }

    /// A switch's name: an on / off pair shows its base name ("Moon Jump"), every other entry its key.
    public static func title(of entry: CheatEntry) -> String {
        guard entry.pairName != nil, !entry.pairOff, let split = CheatFile.onOffSplit(entry.rawName), !split.off else {
            return entry.name
        }
        return split.base
    }

    public static func otherBuild(_ build: String) -> String { "Build \(build) — not used by this version" }

    public static func running(gameName: String) -> String {
        "\(gameName) is running: change cheats in its Cheats panel (⌘⇧C)."
    }

    public static let safeMode = "The last session closed unexpectedly with cheats on. Next start, cheats begin off; "
        + "turn them back on here or in the game's Cheats panel (⌘⇧C)."
}

extension CheatInstall {
    /// Which of several added files to install: one named for this build first, else the only unnamed one.
    public enum Pick: Equatable {
        case file(Int, unnamed: Bool)
        /// More than one unnamed file and none named for this build.
        case several
        /// Nothing installable: the most telling refusal (another build, then another title, then the rest).
        case nothing(Decision?)
    }

    public static func pick(_ decisions: [Decision]) -> Pick {
        if let i = decisions.firstIndex(where: { if case .install = $0 { true } else { false } }) {
            return .file(i, unnamed: false)
        }
        let unnamed = decisions.indices.filter { if case .confirmUnnamed = decisions[$0] { true } else { false } }
        if unnamed.count == 1 { return .file(unnamed[0], unnamed: true) }
        if unnamed.count > 1 { return .several }
        let rank: (Decision) -> Int = {
            switch $0 {
            case .otherBuild: 0
            case .otherTitle: 1
            default: 2
            }
        }
        return .nothing(decisions.min { rank($0) < rank($1) })
    }
}
