import Foundation

/// The Setup check's cards, in screen order: the player's folders first,
/// then prerequisites for building games.
public enum SetupItemID: String, CaseIterable, Codable {
    case library, sources, xcode, metal, engine, runtime, keys
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
    /// While working: how far it has got, for the card's bar; nil draws a moving bar.
    public var progress: Double? = nil
    /// Optional choices stay visible without counting as unfinished Setup steps.
    public var isRequired: Bool = true
    /// Ready, but with something NX Library has not tested (the newest engine): an orange chip, no alarm.
    public var isUntested: Bool = false
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
    public var engine: EngineFacts
    public var engineFolder: URL
    public var pinnedCommit: String
    /// nil when the bundled Python, its modules and the tools all run.
    public var runtimeProblem: String?
    public var keys: KeySummary?
    public var keysError: String?
    /// Only engines with an extracted-folder input can build without prod.keys.
    public var keysOptional: Bool = false
    /// nil: no folder chosen.
    public var libraryReadable: Bool?
    /// Read access permits discovery; new builds also need permission to write here.
    public var libraryWritable: Bool? = nil
    public var libraryFolder: URL? = nil
    /// Your games can ask for a choice until the user chooses a folder or accepts the default with Skip.
    public var libraryNeedsConfirmation: Bool = false
    public var sourcesFolder: URL? = nil
    public var sourcesReadable: Bool? = nil
    public var extractedFoldersSupported: Bool = false
    /// "27.1"; nil when xcodebuild did not say.
    public var xcodeVersion: String?
    public var requirements: ToolchainRequirements
    /// The checkout's HEAD is an ancestor of the pin (an NX Library update brought a newer engine); false when it
    /// is ahead or elsewhere; nil when git cannot tell (the pin is not fetched yet, so it is newer).
    public var engineBehind: Bool?
    /// The newest nxnative the player chose in Settings → Engine; nil while the tested engine is in use.
    public var newestEngine: NewestEngineChoice? = nil

    public init(xcodeStatus: Int32?, metalVersion: String?, certifiedMetal: String, allowUntested: Bool,
                engine: EngineFacts, engineFolder: URL, pinnedCommit: String,
                runtimeProblem: String?, keys: KeySummary?, keysError: String?, libraryReadable: Bool?,
                xcodeVersion: String? = nil,
                requirements: ToolchainRequirements = .current, engineBehind: Bool? = nil) {
        self.xcodeStatus = xcodeStatus
        self.metalVersion = metalVersion
        self.certifiedMetal = certifiedMetal
        self.allowUntested = allowUntested
        self.engine = engine
        self.engineFolder = engineFolder
        self.pinnedCommit = pinnedCommit
        self.runtimeProblem = runtimeProblem
        self.keys = keys
        self.keysError = keysError
        self.libraryReadable = libraryReadable
        self.xcodeVersion = xcodeVersion
        self.requirements = requirements
        self.engineBehind = engineBehind
    }
}

/// What a running action shows over the probed state until it finishes.
public enum SetupOverride: Equatable {
    case working(String, progress: Double? = nil, detail: String? = nil)
    case needsYou(String), failed(String)
}

public enum SetupCheck {
    /// The technical screen has no folder choices; those belong to Your games and Settings → Library.
    public static func requirements(_ items: [SetupItem]) -> [SetupItem] {
        items.filter { $0.id != .library && $0.id != .sources }
    }

    public static func items(from facts: SetupFacts) -> [SetupItem] {
        SetupItemID.allCases.map { item($0, facts) }
    }

    public static func applying(_ overrides: [SetupItemID: SetupOverride], to items: [SetupItem]) -> [SetupItem] {
        items.map { item in
            guard let override = overrides[item.id] else { return item }
            var item = item
            switch override {
            case .working(let chip, let progress, let detail):
                item.state = .working
                item.chip = progress.map { "\(chip) \(Int(($0 * 100).rounded()))%" } ?? chip
                item.progress = progress
                if let detail { item.detail = detail }
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

    /// The cards NX Library fixes by itself, in card order: anything missing it can
    /// install, the certified Metal compiler and the pinned engine commit. Since nxnative 641636e2 the
    /// engine's tools are native executables, so there is no .NET to install or update.
    public static func automatic(_ items: [SetupItem]) -> [SetupItemID] {
        let xcodeReady = items.first { $0.id == .xcode }?.state == .ready
        return items.compactMap { item in
            guard item.state != .working, item.actionTitle != nil else { return nil }
            switch item.id {
            case .metal:
                // Metal comes through Xcode.
                return xcodeReady && (item.state == .missing || item.state == .warning) ? item.id : nil
            case .engine:
                return item.state == .missing || item.state == .warning ? item.id : nil
            default:
                return nil
            }
        }
    }

    /// The screen opens by itself only when a card that was ready has broken,
    /// never for something the player has not set up yet.
    public static func shouldReopen(previous: [SetupItemID: SetupState], current: [SetupItem]) -> Bool {
        requirements(current).contains { item in
            item.isRequired && previous[item.id] == .ready
                && (item.state == .missing || item.state == .warning || item.state == .failed)
        }
    }

    private static func item(_ id: SetupItemID, _ f: SetupFacts) -> SetupItem {
        switch id {
        case .xcode:
            let about = L10n.text("Apple's developer tools. Every game is compiled with them.")
            switch f.xcodeStatus {
            case nil:
                return SetupItem(id: id, title: L10n.text("Xcode"), state: .missing, chip: "NOT INSTALLED", about: about,
                                 detail: L10n.text("Get it from the App Store, then open it once."), actionTitle: L10n.text("Get Xcode"))
            case 69?:
                return SetupItem(id: id, title: L10n.text("Xcode"), state: .needsYou, chip: "OPEN XCODE ONCE", about: about,
                                 detail: L10n.text("Open Xcode and accept its licence; it then installs its components."),
                                 actionTitle: L10n.text("Open Xcode"))
            default:
                let minimum = f.requirements.minimumXcode
                if let version = f.xcodeVersion, VersionNumber.isOlder(version, than: minimum) {
                    return SetupItem(id: id, title: L10n.text("Xcode"), state: .needsYou, chip: "UPDATE XCODE", about: about,
                                     detail: L10n.format("Xcode %@ is installed; the engine needs %@ or newer. Update it from the App Store.", [String(describing: (version)), String(describing: (minimum))]),
                                     actionTitle: L10n.text("Open App Store"))
                }
                return ready(id, "Xcode", about, f.xcodeVersion.map { L10n.format("Xcode %@, installed and set up.", [String(describing: ($0))]) } ?? L10n.text("Installed and set up."))
            }
        case .metal:
            let about = L10n.text("Compiles each game's shaders for this Mac's GPU.")
            guard let version = f.metalVersion else {
                return SetupItem(id: id, title: L10n.text("Metal compiler"), state: .missing, chip: "NOT INSTALLED",
                                 about: about, detail: L10n.text("NX Library downloads it through Xcode."), actionTitle: L10n.text("Install"))
            }
            if version == f.certifiedMetal {
                return ready(id, "Metal compiler", about, L10n.format("Version %@, the one this engine is tested with.", [String(describing: (version))]))
            }
            if f.allowUntested {
                return ready(id, "Metal compiler", about,
                             L10n.format("Version %@; the untested toolchain override is on, so builds may differ.", [String(describing: (version))]))
            }
            if f.requirements.metalDownload(for: f.certifiedMetal) != nil {
                return SetupItem(id: id, title: L10n.text("Metal compiler"), state: .warning, chip: "NOT CERTIFIED", about: about,
                                 detail: L10n.format("Version %@; the engine is tested with %@. NX Library installs %@ through Xcode.", [String(describing: (version)), String(describing: (f.certifiedMetal)), String(describing: (f.certifiedMetal))]),
                                 actionTitle: L10n.format("Install %@", [String(describing: (f.certifiedMetal))]))
            }
            return SetupItem(id: id, title: L10n.text("Metal compiler"), state: .warning, chip: "WAITING FOR ENGINE", about: about,
                             detail: L10n.format("Version %@ came with this Xcode; the engine is tested with %@. New builds wait for an NX Library update tested with it. Games you built still play.", [String(describing: (version)), String(describing: (f.certifiedMetal))]),
                             actionTitle: nil)
        case .engine:
            let about = L10n.text("nxnative, used as it is upstream, at the commit this NX Library is tested with.")
            let short = String(f.pinnedCommit.prefix(7))
            switch f.engine {
            case .missing:
                return SetupItem(id: id, title: L10n.text("nxnative engine"), state: .missing, chip: "NOT INSTALLED", about: about,
                                 detail: L10n.format("NX Library clones it into %@ at %@.", [String(describing: (f.engineFolder.path)), String(describing: (short))]), actionTitle: L10n.text("Clone"))
            case .notACheckout:
                return SetupItem(id: id, title: L10n.text("nxnative engine"), state: .warning, chip: "NOT A CHECKOUT", about: about,
                                 detail: L10n.format("%@ is not a git checkout of nxnative. Move it away, then check again.", [String(describing: (f.engineFolder.path))]),
                                 actionTitle: nil)
            case .checkout(_, true):
                return SetupItem(id: id, title: L10n.text("nxnative engine"), state: .warning, chip: "LOCAL CHANGES", about: about,
                                 detail: L10n.format("%@ has changed files. NX Library never touches them: put them aside, then check again.", [String(describing: (f.engineFolder.path))]),
                                 actionTitle: nil)
            case .checkout(let head, false) where head == f.newestEngine?.commit && head != f.pinnedCommit:
                // The player's own choice: ready, never "other version", and A goes back to the tested engine.
                var card = ready(id, L10n.text("nxnative engine"), NewestEngineCopy.note,
                                 NewestEngineCopy.setupDetail(choice: f.newestEngine!, tested: f.pinnedCommit))
                card.chip = "NEWEST ENGINE"
                card.isUntested = true
                card.actionTitle = L10n.text("Back to tested")
                return card
            case .checkout(let head, false) where head != f.pinnedCommit:
                // Warning either way: Setup reopens for it and Install all runs it.
                if f.engineBehind == false {
                    return SetupItem(id: id, title: L10n.text("nxnative engine"), state: .warning, chip: "OTHER VERSION", about: about,
                                     detail: L10n.format("The engine here is at %@, not the %@ this NX Library is tested with. Switch moves it to %@. Games you built keep playing.", [String(describing: (head.prefix(7))), String(describing: (short)), String(describing: (short))]),
                                     actionTitle: L10n.text("Switch"))
                }
                return SetupItem(id: id, title: L10n.text("nxnative engine"), state: .warning, chip: "UPDATE READY", about: about,
                                 detail: L10n.format("This NX Library uses nxnative %@; the engine here is at %@. Update downloads it and switches to it. Games you built keep playing.", [String(describing: (short)), String(describing: (head.prefix(7)))]),
                                 actionTitle: L10n.text("Update"))
            case .checkout:
                return ready(id, L10n.text("nxnative engine"), about, "At \(short) in \(f.engineFolder.path).")
            }
        case .runtime:
            let about = L10n.text("Python 3.14 with its modules, zstd and glslang, inside NX Library.")
            if let problem = f.runtimeProblem {
                return SetupItem(id: id, title: L10n.text("Python and tools"), state: .failed, chip: "REINSTALL APP", about: about,
                                 detail: L10n.format("%@. Reinstall NX Library from its DMG.", [String(describing: (problem))]), actionTitle: nil)
            }
            return SetupItem(id: id, title: L10n.text("Python and tools"), state: .ready, chip: "✓ INCLUDED", about: about,
                             detail: L10n.text("Nothing to install."), actionTitle: nil)
        case .keys:
            let about = L10n.text("Your console's prod.keys, which unlock your own games. They stay on this Mac.")
            if let keys = f.keys {
                return SetupItem(id: id, title: L10n.text("Keys"), state: .ready, chip: "✓ IMPORTED", about: about,
                                 detail: L10n.format("Header key and %@ application key generations.", [String(describing: (keys.applicationKeyGenerations.count))]),
                                 actionTitle: L10n.text("Replace"))
            }
            if f.keysOptional {
                return SetupItem(id: id, title: L10n.text("Keys"), state: .ready, chip: "OPTIONAL", about: about,
                                 detail: L10n.text("Needed for NSP/XCI packages. Extracted folders do not use keys."), actionTitle: L10n.text("Choose file"))
            }
            return SetupItem(id: id, title: L10n.text("Keys"), state: .missing, chip: "NOT IMPORTED", about: about,
                             detail: f.keysError ?? L10n.text("Choose your prod.keys file."), actionTitle: L10n.text("Choose file"))
        case .library:
            let about = GameFoldersCopy.appsAbout
            if f.libraryNeedsConfirmation {
                return SetupItem(id: id, title: GameFoldersCopy.appsTitle, state: .needsYou, chip: "CHOOSE FOLDER", about: about,
                                 detail: f.libraryFolder.map { L10n.format("Choose this folder or another: %@", [String(describing: ($0.path))]) }
                                    ?? L10n.text("Choose where to keep your game apps. An empty folder is fine."),
                                 actionTitle: L10n.text("Choose folder"))
            }
            switch f.libraryReadable {
            case nil:
                return SetupItem(id: id, title: GameFoldersCopy.appsTitle, state: .missing, chip: "NOT CHOSEN", about: about,
                                 detail: L10n.text("Choose the folder containing your game apps."), actionTitle: L10n.text("Choose folder"))
            case false?:
                return SetupItem(id: id, title: GameFoldersCopy.appsTitle, state: .warning, chip: "NOT READABLE", about: about,
                                 detail: f.libraryFolder.map { L10n.format("Cannot read %@. Reconnect it or choose another.", [String(describing: ($0.path))]) }
                                    ?? L10n.text("NX Library cannot read this folder. Reconnect it or choose another."), actionTitle: L10n.text("Choose folder"))
            case true?:
                if f.libraryWritable == false {
                    return SetupItem(id: id, title: GameFoldersCopy.appsTitle, state: .warning, chip: "READ ONLY", about: about,
                                     detail: L10n.text("Choose a writable folder for new builds. Existing apps still play."),
                                     actionTitle: L10n.text("Change"))
                }
                return SetupItem(id: id, title: GameFoldersCopy.appsTitle, state: .ready, chip: "✓ READY", about: about,
                                 detail: [GameFoldersCopy.appsContents, f.libraryFolder?.path].compactMap { $0 }.joined(separator: "\n"),
                                 actionTitle: L10n.text("Change"))
            }
        case .sources:
            let about = GameFoldersCopy.sourcesAbout(extractedFolders: f.extractedFoldersSupported)
            switch f.sourcesReadable {
            case nil:
                return SetupItem(id: id, title: GameFoldersCopy.sourcesTitle, state: .ready, chip: "OPTIONAL", about: about,
                                 detail: L10n.text("Existing game apps play without sources. Choose later in Settings → Library."),
                                 actionTitle: L10n.text("Choose folder"), isRequired: false)
            case false?:
                return SetupItem(id: id, title: GameFoldersCopy.sourcesTitle, state: .warning, chip: "FOLDER UNAVAILABLE", about: about,
                                 detail: f.sourcesFolder.map { L10n.format("Unavailable: %@. Existing game apps still play.", [String(describing: ($0.path))]) }
                                    ?? L10n.text("Reconnect this folder or choose another. Existing game apps still play."),
                                 actionTitle: L10n.text("Change"), isRequired: false)
            case true?:
                return SetupItem(id: id, title: GameFoldersCopy.sourcesTitle, state: .ready, chip: "✓ CHOSEN", about: about,
                                 detail: f.sourcesFolder?.path ?? L10n.text("Ready to find game sources."), actionTitle: L10n.text("Change"), isRequired: false)
            }
        }
    }

    private static func ready(_ id: SetupItemID, _ title: String, _ about: String, _ detail: String) -> SetupItem {
        SetupItem(id: id, title: title, state: .ready, chip: "✓ READY", about: about, detail: detail, actionTitle: nil)
    }
}
