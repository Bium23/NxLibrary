import Foundation

/// The Setup check's cards, in screen order: what NX Library installs first,
/// then what the player brings.
public enum SetupItemID: String, CaseIterable, Codable {
    case xcode, metal, dotnet, engine, runtime, keys, library
}

public enum SetupState: String, Codable, Equatable {
    case ready, missing, needsYou, working, warning, failed
}

/// One card: a short uppercase chip on the card, the rest in the panel below.
public struct SetupItem: Identifiable, Equatable {
    public let id: SetupItemID
    public var title: String
    public var state: SetupState
    public var chip: String
    public var about: String
    public var detail: String
    /// What A does on the card ("Install", "Clone"…); nil when A does nothing.
    public var actionTitle: String?
}

public enum EngineFacts: Equatable {
    case missing, notACheckout
    case checkout(head: String, dirty: Bool)
}

/// What a probe found; `SetupCheck.items(from:)` turns it into cards.
public struct SetupFacts: Equatable {
    /// nil: no usable Xcode; 69: its licence or first launch is not done.
    public var xcodeStatus: Int32?
    public var metalVersion: String?
    public var certifiedMetal: String
    public var allowUntested: Bool
    public var dotnetSDKs: [String]
    public var engine: EngineFacts
    public var engineFolder: URL
    public var pinnedCommit: String
    /// nil when the bundled Python, its modules and the tools all run.
    public var runtimeProblem: String?
    public var keys: KeySummary?
    public var keysError: String?
    /// nil: no folder chosen.
    public var libraryWritable: Bool?

    public init(xcodeStatus: Int32?, metalVersion: String?, certifiedMetal: String, allowUntested: Bool,
                dotnetSDKs: [String], engine: EngineFacts, engineFolder: URL, pinnedCommit: String,
                runtimeProblem: String?, keys: KeySummary?, keysError: String?, libraryWritable: Bool?) {
        self.xcodeStatus = xcodeStatus
        self.metalVersion = metalVersion
        self.certifiedMetal = certifiedMetal
        self.allowUntested = allowUntested
        self.dotnetSDKs = dotnetSDKs
        self.engine = engine
        self.engineFolder = engineFolder
        self.pinnedCommit = pinnedCommit
        self.runtimeProblem = runtimeProblem
        self.keys = keys
        self.keysError = keysError
        self.libraryWritable = libraryWritable
    }
}

/// What a running action shows over the probed state until it finishes.
public enum SetupOverride: Equatable {
    case working(String), needsYou(String), failed(String)
}

public enum SetupCheck {
    public static func items(from facts: SetupFacts) -> [SetupItem] {
        SetupItemID.allCases.map { item($0, facts) }
    }

    public static func applying(_ overrides: [SetupItemID: SetupOverride], to items: [SetupItem]) -> [SetupItem] {
        items.map { item in
            guard let override = overrides[item.id] else { return item }
            var item = item
            switch override {
            case .working(let chip):
                item.state = .working
                item.chip = chip
                item.actionTitle = nil
            case .needsYou(let chip):
                item.state = .needsYou
                item.chip = chip
            case .failed(let message):
                item.state = .failed
                item.chip = "COULDN'T INSTALL"
                item.detail = message
            }
            return item
        }
    }

    /// The screen opens by itself only when a card that was ready has broken,
    /// never for something the player has not set up yet.
    public static func shouldReopen(previous: [SetupItemID: SetupState], current: [SetupItem]) -> Bool {
        current.contains { item in
            previous[item.id] == .ready && (item.state == .missing || item.state == .warning || item.state == .failed)
        }
    }

    private static func item(_ id: SetupItemID, _ f: SetupFacts) -> SetupItem {
        switch id {
        case .xcode:
            let about = "Apple's developer tools. Every game is compiled with them."
            switch f.xcodeStatus {
            case nil:
                return SetupItem(id: id, title: "Xcode", state: .missing, chip: "NOT INSTALLED", about: about,
                                 detail: "Get it from the App Store, then open it once.", actionTitle: "Get Xcode")
            case 69?:
                return SetupItem(id: id, title: "Xcode", state: .needsYou, chip: "OPEN XCODE ONCE", about: about,
                                 detail: "Open Xcode and accept its licence; it then installs its components.",
                                 actionTitle: "Open Xcode")
            default:
                return ready(id, "Xcode", about, "Installed and set up.")
            }
        case .metal:
            let about = "Compiles each game's shaders for this Mac's GPU."
            guard let version = f.metalVersion else {
                return SetupItem(id: id, title: "Metal compiler", state: .missing, chip: "NOT INSTALLED",
                                 about: about, detail: "NX Library downloads it through Xcode.", actionTitle: "Install")
            }
            if version == f.certifiedMetal {
                return ready(id, "Metal compiler", about, "Version \(version), the one this engine is tested with.")
            }
            if f.allowUntested {
                return ready(id, "Metal compiler", about,
                             "Version \(version); the untested toolchain override is on, so builds may differ.")
            }
            return SetupItem(id: id, title: "Metal compiler", state: .warning, chip: "NOT CERTIFIED", about: about,
                             detail: "Version \(version); the engine is tested with \(f.certifiedMetal). New builds stay blocked unless you turn on the untested toolchain override in Settings › Engine.",
                             actionTitle: nil)
        case .dotnet:
            let about = "Builds the engine's tools that read each game's package."
            if f.dotnetSDKs.contains(where: { $0.hasPrefix("10.") }) {
                return ready(id, ".NET 10 SDK", about, "Installed.")
            }
            return SetupItem(id: id, title: ".NET 10 SDK", state: .missing, chip: "NOT INSTALLED", about: about,
                             detail: "NX Library downloads Microsoft's installer; macOS asks for your password.",
                             actionTitle: "Install")
        case .engine:
            let about = "nxnative, used as it is upstream, at the commit this NX Library is tested with."
            let short = String(f.pinnedCommit.prefix(7))
            switch f.engine {
            case .missing:
                return SetupItem(id: id, title: "nxnative engine", state: .missing, chip: "NOT INSTALLED", about: about,
                                 detail: "NX Library clones it into \(f.engineFolder.path) at \(short).", actionTitle: "Clone")
            case .notACheckout:
                return SetupItem(id: id, title: "nxnative engine", state: .warning, chip: "NOT A CHECKOUT", about: about,
                                 detail: "\(f.engineFolder.path) is not a git checkout of nxnative. Move it away, then check again.",
                                 actionTitle: nil)
            case .checkout(_, true):
                return SetupItem(id: id, title: "nxnative engine", state: .warning, chip: "LOCAL CHANGES", about: about,
                                 detail: "\(f.engineFolder.path) has changed files. NX Library never touches them: put them aside, then check again.",
                                 actionTitle: nil)
            case .checkout(let head, false) where head != f.pinnedCommit:
                return SetupItem(id: id, title: "nxnative engine", state: .warning, chip: "WRONG COMMIT", about: about,
                                 detail: "At \(head.prefix(7)); this NX Library is tested with \(short).",
                                 actionTitle: "Check out")
            case .checkout:
                return ready(id, "nxnative engine", about, "At \(short) in \(f.engineFolder.path).")
            }
        case .runtime:
            let about = "Python 3.14 with its modules, zstd and glslang, inside NX Library."
            if let problem = f.runtimeProblem {
                return SetupItem(id: id, title: "Python and tools", state: .failed, chip: "REINSTALL APP", about: about,
                                 detail: "\(problem). Reinstall NX Library from its DMG.", actionTitle: nil)
            }
            return SetupItem(id: id, title: "Python and tools", state: .ready, chip: "✓ INCLUDED", about: about,
                             detail: "Nothing to install.", actionTitle: nil)
        case .keys:
            let about = "Your console's prod.keys, which unlock your own games. They stay on this Mac."
            if let keys = f.keys {
                return SetupItem(id: id, title: "Keys", state: .ready, chip: "✓ IMPORTED", about: about,
                                 detail: "Header key and \(keys.applicationKeyGenerations.count) application key generations.",
                                 actionTitle: "Replace")
            }
            return SetupItem(id: id, title: "Keys", state: .missing, chip: "NOT IMPORTED", about: about,
                             detail: f.keysError ?? "Choose your prod.keys file.", actionTitle: "Choose file")
        case .library:
            let about = "Where built games go."
            switch f.libraryWritable {
            case nil:
                return SetupItem(id: id, title: "Library folder", state: .missing, chip: "NOT CHOSEN", about: about,
                                 detail: "Choose a folder for your games.", actionTitle: "Choose folder")
            case false?:
                return SetupItem(id: id, title: "Library folder", state: .warning, chip: "NOT WRITABLE", about: about,
                                 detail: "NX Library cannot write there. Choose another folder.", actionTitle: "Choose folder")
            case true?:
                return SetupItem(id: id, title: "Library folder", state: .ready, chip: "✓ READY", about: about,
                                 detail: "Games build here.", actionTitle: "Change")
            }
        }
    }

    private static func ready(_ id: SetupItemID, _ title: String, _ about: String, _ detail: String) -> SetupItem {
        SetupItem(id: id, title: title, state: .ready, chip: "✓ READY", about: about, detail: detail, actionTitle: nil)
    }
}
