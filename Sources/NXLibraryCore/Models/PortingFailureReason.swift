import Foundation

/// Why a porting stopped, in words a player can act on: recognised from the engine's own messages
/// (the table idea is NX2Apple's, MIT; see NOTICE) or from what NX Library checked itself. Saved with
/// the game, so the home still explains a failure after a relaunch.
public struct PortingFailureReason: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case rosetta, translator, zbic, cltSelected, otherMetal, shaderRegression, damagedNSP, a32Program
        case keys, keysTooOld, keysWrong, severalGames, noTitleID, diskFull, driveMissing, cloudFolder
        case noProfile, unknown
    }

    public var kind: Kind
    /// What the message adds: GB needed, a drive or folder, a firmware, a file, a rewrite address.
    public var detail: String?

    // Keep the persisted kind readable by older launchers during rollback.
    static let missingTicketDetail = "missing-common-ticket"
    private var isMissingTicket: Bool { kind == .keys && detail == Self.missingTicketDetail }
    /// Damage `--allow-damaged` cannot get past (a filesystem's own tables, a cut-off package).
    static let unreadableDamageDetail = "unreadable"
    private var isUnreadableDamage: Bool { kind == .damagedNSP && detail == Self.unreadableDamageDetail }
    /// The game lacks the language its Game options ask for; the detail names it ("missing-language:Japanese").
    static let missingLanguagePrefix = "missing-language:"
    private var missingLanguage: String? {
        guard kind == .unknown, let detail, detail.hasPrefix(Self.missingLanguagePrefix) else { return nil }
        return String(detail.dropFirst(Self.missingLanguagePrefix.count))
    }

    public init(kind: Kind, detail: String? = nil) {
        self.kind = kind
        self.detail = detail
    }

    /// The reason for a key check that stops a porting; nil when the keys fit or cannot be checked.
    public static func from(_ outcome: KeyCheck.Outcome) -> PortingFailureReason? {
        switch outcome {
        case .fits, .cannotCheck: return nil
        case .tooOld(_, let generation, _):
            return PortingFailureReason(kind: .keysTooOld, detail: KeyCheck.firmware(forGeneration: generation))
        case .wrongHeaderKey(let file): return PortingFailureReason(kind: .keysWrong, detail: file)
        case .noHeaderKey, .unreadableKeys: return PortingFailureReason(kind: .keys)
        }
    }

    // MARK: - Copy

    public var title: String {
        switch kind {
        case .rosetta: return L10n.text("The build ran as Intel code")
        case .translator: return L10n.text("The shader translator did not run")
        case .zbic: return L10n.text("A Python package is missing")
        case .cltSelected: return L10n.text("Xcode is not selected")
        case .otherMetal: return L10n.text("Your Metal compiler is not certified")
        case .shaderRegression: return L10n.text("Some shaders broke in this engine")
        case .damagedNSP: return L10n.text("Some game files are damaged")
        case .a32Program: return L10n.text("This game is not supported")
        case .keys: return isMissingTicket ? L10n.text("Game ticket missing") : L10n.text("Your keys could not be read")
        case .keysTooOld: return L10n.text("Your keys are too old")
        case .keysWrong: return L10n.text("These keys do not open the game")
        case .severalGames: return L10n.text("The folder holds more than one game")
        case .noTitleID: return L10n.text("No game found in the files")
        case .diskFull: return L10n.text("Not enough disk space")
        case .driveMissing: return L10n.text("A drive is not connected")
        case .cloudFolder: return L10n.text("The library is in a cloud folder")
        case .noProfile: return L10n.text("This game is not supported yet")
        case .unknown: return missingLanguage == nil ? L10n.text("The porting stopped") : L10n.text("The game does not have this language")
        }
    }

    public func what(game: String) -> String {
        switch kind {
        case .rosetta: return L10n.text("The porting started an Intel Python, so its tools ran under Rosetta.")
        case .translator: return L10n.text("The engine's shader translator is missing or damaged.")
        case .zbic: return L10n.text("The engine needs the zbic package to read this game's code.")
        case .cltSelected: return L10n.text("The selected developer folder is the Command Line Tools, which cannot build the app.")
        case .otherMetal: return L10n.text("The shaders were tested with another Metal compiler than the one on this Mac.")
        case .shaderRegression: return L10n.text("Shaders that translated before fail with the engine's current translator.")
        case .damagedNSP: return isUnreadableDamage
            ? L10n.format("%@'s package is cut off or its own tables fail their hash check: an incomplete copy or a broken download.", [String(describing: (game))])
            : L10n.format("Some files of %@ fail their hash check: an incomplete copy or a broken download.", [String(describing: (game))])
        case .a32Program: return L10n.format("%@ is a 32-bit ARM program, and nxnative runs only 64-bit games.", [String(describing: (game))])
        case .keys: return isMissingTicket
            ? L10n.format("The package has no common ticket needed to open %@.", [String(describing: (game))])
            : L10n.text("prod.keys is missing, unreadable or has no header_key.")
        case .keysTooOld: return L10n.format("%@ needs keys newer than the ones you imported.", [String(describing: (game))])
        case .keysWrong: return L10n.format("header_key does not open %@.", [String(describing: (detail ?? "the game's files"))])
        case .severalGames: return L10n.text("Each porting needs one game; this folder holds files of several.")
        case .noTitleID: return L10n.text("None of the files holds a game the engine can read.")
        case .diskFull:
            if let gb = detail { return L10n.format("The porting needs at least %@ GB free on the work volume.", [String(describing: (gb))]) }
            return L10n.text("The disk filled up during the porting.")
        case .driveMissing: return L10n.format("%@'s files are on %@ that is not connected.", [String(describing: (game)), String(describing: (detail ?? L10n.text("a drive")))])
        case .cloudFolder: return L10n.text("Files in iCloud Drive or another synced folder carry data that code signing refuses.")
        case .noProfile:
            let at = detail.map { L10n.format(" (rewrite stopped at 0x%@)", [String(describing: ($0))]) } ?? ""
            return L10n.format("%@ has no verified nxnative game profile%@; the pinned engine does not support it yet.", [String(describing: (game)), String(describing: (at))])
        case .unknown:
            if let language = missingLanguage { return L10n.format("%@ has no %@, the language set in its Game options.", [String(describing: (game)), String(describing: (language))]) }
            return L10n.text("The engine stopped without a message NX Library recognises.")
        }
    }

    public var next: String {
        switch kind {
        case .rosetta: return L10n.text("Reinstall NX Library so the porting uses its own arm64 Python.")
        case .translator: return L10n.text("Open Setup and check the nxnative engine card.")
        case .zbic: return L10n.text("Update NX Library: its built-in Python includes zbic from 0.1.3.2. Installing zbic with pip does not reach it.")
        case .cltSelected: return L10n.text("Open Setup and select Xcode.")
        case .otherMetal: return L10n.text("Install the certified compiler from Setup, or allow untested toolchains in Settings → Engine.")
        case .shaderRegression: return L10n.text("Port anyway to keep the broken shaders out, or wait for an engine update.")
        case .damagedNSP: return isUnreadableDamage
            ? L10n.text("Dump or download the game again.")
            : L10n.text("Dump or download the game again, or port anyway with the damaged files as read.")
        case .a32Program: return L10n.text("Nothing to fix here: this title cannot run.")
        case .keys: return isMissingTicket
            ? L10n.text("Export the complete game package again from your console, including its ticket.")
            : L10n.text("Import prod.keys from your console again.")
        case .keysTooOld:
            if let firmware = detail { return L10n.format("Dump prod.keys again from a console on firmware %@ or later.", [String(describing: (firmware))]) }
            return L10n.text("Dump prod.keys again from an up-to-date console.")
        case .keysWrong: return L10n.text("Import prod.keys from the console these files were dumped with.")
        case .severalGames: return L10n.text("Choose a folder with one game's base, update and DLC.")
        case .noTitleID: return L10n.text("Check that the files are complete NSP, NSZ or XCI dumps.")
        case .diskFull: return L10n.text("Free some space, then try again.")
        case .driveMissing: return L10n.format("Connect %@, then try again.", [String(describing: (detail ?? L10n.text("the drive")))])
        case .cloudFolder: return L10n.text("Move the library to a folder outside iCloud Drive.")
        case .noProfile: return L10n.text("Watch for an engine update that adds this game.")
        case .unknown:
            if missingLanguage != nil { return L10n.text("In Game options, set Language to Game Default or to one of the game's languages, then port again.") }
            return L10n.text("Open the log, or copy diagnostics for a bug report.")
        }
    }

    public var action: PortingFailureAction {
        switch kind {
        case .shaderRegression: return .portAnyway(flag: "--allow-shader-regressions")
        case .damagedNSP: return isUnreadableDamage ? .none : .portAnyway(flag: "--allow-damaged")
        case .otherMetal: return .openEngineSettings
        case .translator, .cltSelected: return .openSetup
        case .keys: return isMissingTicket ? .none : .importKeys
        case .keysTooOld, .keysWrong: return .importKeys
        case .diskFull: return .openStorage
        default: return .none
        }
    }
}

/// The one action a failure screen offers beside Open log and Try again.
public enum PortingFailureAction: Equatable, Sendable {
    case portAnyway(flag: String)
    case openEngineSettings
    case openSetup
    case importKeys
    case openStorage
    case none
}

public enum PortingFailureClassifier {
    /// One row per engine message. `pattern` is searched in the log (a regular expression; the
    /// engine's JSON progress wraps each line in `{"ev": "say", "msg": …}`, so nothing is anchored).
    /// `engineFragment` is a fixed part of the message as the engine's source writes it, checked by
    /// `PortingFailureEngineTests` against the pinned commit; nil for messages from the OS or codesign.
    public static let table: [(id: String, kind: PortingFailureReason.Kind, pattern: String, engineFragment: String?)] = [
        ("rosetta.intel", .rosetta, "is an Intel one running under Rosetta", "is an Intel one running under Rosetta"),
        ("translator.run", .translator, "the shader translator does not run", "the shader translator does not run"),
        ("translator.start", .translator, "the shader translator does not start", "the shader translator does not start"),
        ("zbic.missing", .zbic, "need the zbic package", "need the zbic package"),
        ("clt.selected", .cltSelected, "the selected developer folder is the Command Line Tools",
         "the selected developer folder is the Command Line Tools"),
        ("metal.other", .otherMetal, "Metal compiler is not the one the shaders were tested with",
         "Metal compiler is not the one the shaders were tested with"),
        ("shaders.regression", .shaderRegression, "a change to the translation chain broke them",
         "a change to the translation chain broke them"),
        ("nsp.damaged", .damagedNSP, "files fail the NCA's hash check", "files fail the NCA's hash check"),
        ("nsp.tables", .damagedNSP, "own tables fail the NCA's hash check", "own tables fail the NCA's hash check"),
        ("nsp.truncated", .damagedNSP, "truncated PFS0 (header|file-name table)", "truncated PFS0 "),
        // A NUP or a dump has no NCA hashes: a file whose first bytes are not its format's (b2d46b86 on).
        ("files.format", .damagedNSP, "whose bytes do not start as their names promise",
         "whose bytes do not start as their names promise"),
        ("language.missing", .unknown, #"the game has no [A-Za-z-]+ \([^)]+\); its languages"#, "); its languages: "),
        ("arm32.program", .a32Program, "is a 32-bit ARM program", "is a 32-bit ARM program"),
        ("keys.missing", .keys, #"no such file: [^"\n]*prod\.keys"#, "no such file: "),
        ("keys.tooOld", .keysTooOld, #"prod\.keys has no [^\n]+the keys are older than the game"#,
         "the keys are older than the game"),
        ("keys.ticket", .keys, "the package has no common ticket for it", "the package has no common ticket for it"),
        ("games.several", .severalGames, "more than one game in the folder", "more than one game in the folder"),
        // nxnative 5c4dc18f reads every package's content meta; before it, "no NSP with a readable title ID in ".
        ("games.noTitleID", .noTitleID, "no (NSP with a readable title ID|game package with a readable content meta) in ",
         "no game package with a readable content meta in "),
        ("disk.low", .diskFull, "less than [0-9]+ GB free on the volume of", "GB free on the volume of"),
        ("disk.app", .diskFull, #"the app needs [0-9.]+ GB on the volume of"#, "the app needs "),
        ("disk.full", .diskFull, "No space left on device", nil),
        ("icloud.detritus", .cloudFolder, "resource fork, Finder information, or similar detritus not allowed", nil),
    ]

    /// Inputs first (a drive that is gone makes every later message a consequence), then the table,
    /// then unreadable keys, then the provisional-profile markers (a warning that also precedes real
    /// stops, so it is matched last), else `unknown`.
    public static func classify(log: String, keysPath: String, sourcePaths: [String],
                                volumes: String = "/Volumes",
                                isReadable: (String) -> Bool = { FileManager.default.isReadableFile(atPath: $0) },
                                isMounted: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
        -> PortingFailureReason {
        let prefix = volumes.hasSuffix("/") ? volumes : volumes + "/"
        for path in [keysPath] + sourcePaths where path.hasPrefix(prefix) {
            guard let name = path.dropFirst(prefix.count).split(separator: "/").first.map(String.init) else { continue }
            if !isMounted(prefix + name) { return PortingFailureReason(kind: .driveMissing, detail: name) }
        }
        for row in table where log.range(of: row.pattern, options: .regularExpression) != nil {
            return PortingFailureReason(kind: row.kind, detail: detail(of: row.kind, in: log))
        }
        if !keysPath.isEmpty, !isReadable(keysPath) { return PortingFailureReason(kind: .keys) }
        if log.contains("provisional game profile") || log.contains("no game profile for") {
            return PortingFailureReason(kind: .noProfile, detail: jumpTableAddress(in: log))
        }
        return PortingFailureReason(kind: .unknown)
    }

    /// The porting's extra arguments with a one-off override: every `--allow-*` except the Metal
    /// gate's `--allow-other-metal` goes, then `flag` is added.
    public static func arguments(_ args: [String], adding flag: String?) -> [String] {
        let rest = args.filter { !$0.hasPrefix("--allow-") || $0 == "--allow-other-metal" }
        guard let flag, flag.hasPrefix("--allow-") else { return rest }
        return rest + [flag]
    }

    private static func detail(of kind: PortingFailureReason.Kind, in log: String) -> String? {
        switch kind {
        case .keys:
            return log.contains("the package has no common ticket for it") ? PortingFailureReason.missingTicketDetail : nil
        case .damagedNSP:
            let unreadable = log.contains("own tables fail the NCA's hash check") || log.contains("truncated PFS0 ")
            return unreadable ? PortingFailureReason.unreadableDamageDetail : nil
        case .unknown:
            guard let r = log.range(of: #"the game has no [A-Za-z-]+ \([^)]+\)"#, options: .regularExpression),
                  let open = log[r].firstIndex(of: "(") else { return nil }
            let name = log[log.index(after: open)..<log.index(before: r.upperBound)]
            return PortingFailureReason.missingLanguagePrefix + name
        case .keysTooOld:
            let prefix = "which came with firmware "
            // Package probes can fail before the final preflight reports the worst requirement.
            let errors = try? NSRegularExpression(pattern: #"prod\.keys has no [^\n]*?the keys are older than the game"#)
            guard let last = errors?.matches(in: log, range: NSRange(log.startIndex..., in: log)).last,
                  let messageRange = Range(last.range, in: log) else { return nil }
            let message = String(log[messageRange])
            guard let range = message.range(of: #"which came with firmware [0-9]+(?:\.[0-9]+){1,2}"#,
                                        options: .regularExpression) else { return nil }
            return String(message[range].dropFirst(prefix.count))
        case .diskFull:
            if let r = log.range(of: "less than [0-9]+ GB free", options: .regularExpression) {
                return log[r].split(separator: " ").dropFirst(2).first.map(String.init)
            }
            if let r = log.range(of: #"the app needs [0-9.]+ GB on the volume of"#, options: .regularExpression) {
                let parts = log[r].split(separator: " ")
                if parts.count >= 4, let num = Double(parts[3]) {
                    return String(Int(ceil(num + 1.0)))
                }
            }
            return nil
        case .noTitleID:
            guard let r = log.range(of: #"no (NSP with a readable title ID|game package with a readable content meta) in [^"\n]+"#,
                                    options: .regularExpression),
                  let folder = log[r].range(of: " in ") else { return nil }
            return String(log[r][folder.upperBound...]).trimmingCharacters(in: .whitespaces)
        default:
            return nil
        }
    }

    static func jumpTableAddress(in log: String) -> String? {
        guard let range = log.range(of: "jump table ", options: .backwards) else { return nil }
        let hex = log[range.upperBound...].prefix { $0.isHexDigit }
        return hex.isEmpty ? nil : String(hex)
    }
}
