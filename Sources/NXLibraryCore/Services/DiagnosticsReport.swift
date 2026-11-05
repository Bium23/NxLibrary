import Foundation

/// A Markdown report for an issue (the idea is NX2Apple's, MIT; see NOTICE). Private by
/// construction: the home folder becomes `~`, a line that looks like key material keeps only the
/// key's name, and no environment variable is ever included.
public enum DiagnosticsReport {
    public struct Inputs {
        public var appVersion = "?"
        public var buildDate: String? = nil
        public var bundleID = "?"
        public var macOS = "?"
        public var chip = "?"
        public var pinnedCommit = "?"
        /// The newest nxnative the player chose instead of the tested pin; nil while the pin is in use.
        public var newestEngine: String? = nil
        /// The engine checkout's HEAD as "<short hash> <subject>"; nil when there is no checkout.
        public var engineHead: String? = nil
        public var xcodePath: String? = nil
        public var xcodeVersion: String? = nil
        public var metalFound: String? = nil
        public var metalCertified: String? = nil
        public var untestedOverride = false
        public var dotnet: String? = nil
        public var python: String? = nil
        public var setupRows: [(name: String, ready: Bool)] = []
        public var keysImported = false
        public var hasHeaderKey = false
        public var keyGenerations = 0
        public var game: (name: String, titleID: String?, built: Bool, toolchainVerified: Bool?, failure: String?)? = nil
        /// The selected game's cheats; nil when it has none NX Library can read. Never names or codes.
        public var cheats: (buildID: String, filePresent: Bool, total: Int, on: Int, broken: Int, masterOn: Bool, safeMode: Bool)? = nil
        public var lastCommand: [String] = []
        public var log: [String] = []
        public var home = NSHomeDirectory()

        public init() {}
    }

    static let logLines = 50

    public static func markdown(_ i: Inputs) -> String {
        func value(_ s: String?) -> String { s.map { $0.isEmpty ? "—" : $0 } ?? "—" }
        func yes(_ b: Bool) -> String { b ? "yes" : "no" }
        var lines = ["# NX Library diagnostics", ""]
        lines += ["## App",
                  "- Version: \(i.appVersion)" + (i.buildDate.map { " (built \($0))" } ?? ""),
                  "- Bundle ID: \(i.bundleID)",
                  "- macOS: \(i.macOS) · \(i.chip)", ""]
        let headHash = i.engineHead?.split(separator: " ").first.map(String.init)
        let matches = headHash.map { !$0.isEmpty && i.pinnedCommit.hasPrefix($0) } ?? false
        lines += ["## Engine",
                  "- Pinned: \(i.pinnedCommit)",
                  "- Newest engine chosen: \(i.newestEngine ?? "no")",
                  "- nxnative HEAD: \(value(i.engineHead))" + (i.engineHead == nil ? "" : (matches ? " (matches)" : " (differs)")),
                  ""]
        lines += ["## Toolchain",
                  "- Xcode: \(value(i.xcodePath)) \(value(i.xcodeVersion))",
                  "- Metal compiler: \(value(i.metalFound)) (certified: \(value(i.metalCertified)))",
                  "- Untested-toolchain override: \(i.untestedOverride ? "on" : "off")",
                  "- .NET SDK: \(value(i.dotnet))",
                  "- Python: \(value(i.python))", ""]
        lines += ["## Setup"] + i.setupRows.map { "- \($0.name): \($0.ready ? "ready" : "missing")" } + [""]
        lines += ["## Keys",
                  "- Imported: \(yes(i.keysImported))",
                  "- header_key present: \(yes(i.hasHeaderKey))",
                  "- Key generations: \(i.keyGenerations)", ""]
        if let g = i.game {
            lines += ["## Selected game",
                      "- \(g.name) (\(value(g.titleID)))",
                      "- Built: \(yes(g.built))",
                      "- Toolchain verified: \(g.toolchainVerified.map(yes) ?? "—")",
                      "- Last porting: \(value(g.failure))",
                      "- Cheats: " + (i.cheats.map { c in
                          "build \(c.buildID), file \(yes(c.filePresent)), \(c.total) cheats, \(c.on) on, "
                              + "\(c.broken) not supported, master \(c.masterOn ? "on" : "off"), safe mode \(yes(c.safeMode))"
                      } ?? "—"), ""]
        }
        lines += ["## Last porting",
                  "```",
                  i.lastCommand.isEmpty ? "(no porting this session)" : i.lastCommand.joined(separator: " "),
                  "```", "",
                  "```"] + i.log.suffix(logLines) + ["```", ""]
        return lines.map { scrub($0, home: i.home) }.joined(separator: "\n")
    }

    private static let keyLine = try! NSRegularExpression(pattern: #"([A-Za-z0-9_]+)\s*=\s*[0-9A-Fa-f]{32,}"#)
    private static let secrets: [(NSRegularExpression, String)] = [
        (#"(?i)(\b(?:proxy-)?authorization\s*[:=]\s*)(?:bearer|basic)\s+[^\s"',;]+"#, "$1<redacted>"),
        (#"(?i)(["']?\b[A-Za-z0-9_-]*(?:api[_-]?key|token|secret|password|passwd)["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;&]+)"#, "$1<redacted>"),
        (#"(?i)(--[A-Za-z0-9_-]*(?:api[_-]?key|token|secret|password|passwd)\s+)(?:"[^"]*"|'[^']*'|\S+)"#, "$1<redacted>"),
        (#"(?i)(https?://)[^/\s:@]+:[^/\s@]+@"#, "$1<redacted>@")
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    /// The home folder as `~`; `name = <32+ hex>` anywhere in the line as `name = <redacted>`.
    public static func scrub(_ line: String, home: String) -> String {
        var out = home.isEmpty || home == "/" ? line : line.replacingOccurrences(of: home, with: "~")
        let range = NSRange(out.startIndex..., in: out)
        out = keyLine.stringByReplacingMatches(in: out, range: range, withTemplate: "$1 = <redacted>")
        for (pattern, replacement) in secrets {
            out = pattern.stringByReplacingMatches(in: out,
                range: NSRange(out.startIndex..., in: out), withTemplate: replacement)
        }
        return out
    }
}
