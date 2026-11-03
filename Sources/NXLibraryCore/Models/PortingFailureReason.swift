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
        case .rosetta: return "The build ran as Intel code"
        case .translator: return "The shader translator did not run"
        case .zbic: return "A Python package is missing"
        case .cltSelected: return "Xcode is not selected"
        case .otherMetal: return "Your Metal compiler is not certified"
        case .shaderRegression: return "Some shaders broke in this engine"
        case .damagedNSP: return "Some game files are damaged"
        case .a32Program: return "This game is not supported"
        case .keys: return isMissingTicket ? "Game ticket missing" : "Your keys could not be read"
        case .keysTooOld: return "Your keys are too old"
        case .keysWrong: return "These keys do not open the game"
        case .severalGames: return "The folder holds more than one game"
        case .noTitleID: return "No game found in the files"
        case .diskFull: return "Not enough disk space"
        case .driveMissing: return "A drive is not connected"
        case .cloudFolder: return "The library is in a cloud folder"
        case .noProfile: return "This game is not supported yet"
        case .unknown: return "The porting stopped"
        }
    }

    public func what(game: String) -> String {
        switch kind {
        case .rosetta: return "The porting started an Intel Python, so its tools ran under Rosetta."
        case .translator: return "The shader translator needs the .NET 10 runtime for this Mac."
        case .zbic: return "The engine needs the zbic package to read this game's code."
        case .cltSelected: return "The selected developer folder is the Command Line Tools, which cannot build the app."
        case .otherMetal: return "The shaders were tested with another Metal compiler than the one on this Mac."
        case .shaderRegression: return "Shaders that translated before fail with the engine's current translator."
        case .damagedNSP: return "Some files of \(game) fail their hash check: an incomplete copy or a broken download."
        case .a32Program: return "\(game) is a 32-bit ARM program, and nxnative runs only 64-bit games."
        case .keys: return isMissingTicket
            ? "The package has no common ticket needed to open \(game)."
            : "prod.keys is missing, unreadable or has no header_key."
        case .keysTooOld: return "\(game) needs keys newer than the ones you imported."
        case .keysWrong: return "header_key does not open \(detail ?? "the game's files")."
        case .severalGames: return "Each porting needs one game; this folder holds files of several."
        case .noTitleID: return "None of the files names a title ID the engine can read."
        case .diskFull:
            if let gb = detail { return "The porting needs at least \(gb) GB free on the work volume." }
            return "The disk filled up during the porting."
        case .driveMissing: return "\(game)'s files are on \(detail ?? "a drive") that is not connected."
        case .cloudFolder: return "Files in iCloud Drive or another synced folder carry data that code signing refuses."
        case .noProfile:
            let at = detail.map { " (rewrite stopped at 0x\($0))" } ?? ""
            return "\(game) has no verified nxnative game profile\(at); the pinned engine does not support it yet."
        case .unknown: return "The engine stopped without a message NX Library recognises."
        }
    }

    public var next: String {
        switch kind {
        case .rosetta: return "Reinstall NX Library so the porting uses its own arm64 Python."
        case .translator: return "Open Setup and install the .NET 10 SDK."
        case .zbic: return "Reinstall NX Library to restore its bundled Python."
        case .cltSelected: return "Open Setup and select Xcode."
        case .otherMetal: return "Install the certified compiler from Setup, or allow untested toolchains in Settings → Engine."
        case .shaderRegression: return "Port anyway to keep the broken shaders out, or wait for an engine update."
        case .damagedNSP: return "Dump or download the game again, or port anyway with the damaged files as read."
        case .a32Program: return "Nothing to fix here: this title cannot run."
        case .keys: return isMissingTicket
            ? "Export the complete game package again from your console, including its ticket."
            : "Import prod.keys from your console again."
        case .keysTooOld:
            if let firmware = detail { return "Dump prod.keys again from a console on firmware \(firmware) or later." }
            return "Dump prod.keys again from an up-to-date console."
        case .keysWrong: return "Import prod.keys from the console these files were dumped with."
        case .severalGames: return "Choose a folder with one game's base, update and DLC."
        case .noTitleID: return "Check that the files are complete NSP, NSZ or XCI dumps."
        case .diskFull: return "Free some space, then try again."
        case .driveMissing: return "Connect \(detail ?? "the drive"), then try again."
        case .cloudFolder: return "Move the library to a folder outside iCloud Drive."
        case .noProfile: return "Watch for an engine update that adds this game."
        case .unknown: return "Open the log, or copy diagnostics for a bug report."
        }
    }

    public var action: PortingFailureAction {
        switch kind {
        case .shaderRegression: return .portAnyway(flag: "--allow-shader-regressions")
        case .damagedNSP: return .portAnyway(flag: "--allow-damaged")
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
        ("arm32.program", .a32Program, "is a 32-bit ARM program", "is a 32-bit ARM program"),
        ("keys.missing", .keys, #"no such file: [^"\n]*prod\.keys"#, "no such file: "),
        ("keys.tooOld", .keysTooOld, #"prod\.keys has no [^\n]+the keys are older than the game"#,
         "the keys are older than the game"),
        ("keys.ticket", .keys, "the package has no common ticket for it", "the package has no common ticket for it"),
        ("games.several", .severalGames, "more than one game in the folder", "more than one game in the folder"),
        ("games.noTitleID", .noTitleID, "no NSP with a readable title ID in ", "no NSP with a readable title ID in "),
        ("disk.low", .diskFull, "less than [0-9]+ GB free on the volume of", "GB free on the volume of"),
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
            guard let r = log.range(of: "less than [0-9]+ GB free", options: .regularExpression) else { return nil }
            return log[r].split(separator: " ").dropFirst(2).first.map(String.init)
        case .noTitleID:
            guard let r = log.range(of: #"no NSP with a readable title ID in [^"\n]+"#, options: .regularExpression)
            else { return nil }
            return String(log[r].dropFirst("no NSP with a readable title ID in ".count))
                .trimmingCharacters(in: .whitespaces)
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
