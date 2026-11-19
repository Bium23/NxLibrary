import AppKit
import Foundation
import NXLibraryCore

/// The Switch Setup's state: the engine (folder, commit, upstream, newest engine), the keys, the environment check
/// and the Metal gate. The screens that show any of it observe it on their own: Settings, Add Game, Game options, the
/// home, the game page and the shell's update offer. It reaches the rest of Arcane only through `app`, the list of
/// what the Porting module will ask of the base.
final class SetupModel: ObservableObject {
    /// The coordinator: library, building state, alerts and the tested pin.
    unowned let app: AppViewModel

    // MARK: - Engine
    @Published var nxnativePath: String = ""
    @Published var isNxnativeValid: Bool = false
    @Published var currentEngineCommit: String? = nil
    @Published var upstreamState: UpstreamCheckState = .idle
    /// The newest nxnative the player chose in Settings → Setup and engine; nil while the tested engine is in use.
    @Published var newestEngineChoice: NewestEngineChoice? = nil {
        didSet {
            if let choice = newestEngineChoice, let data = try? JSONEncoder().encode(choice) {
                AppData.preferences.set(data, forKey: AppViewModel.StorageKeys.newestEngineChoice)
            } else {
                AppData.preferences.removeObject(forKey: AppViewModel.StorageKeys.newestEngineChoice)
            }
        }
    }
    /// Whether upstream main can be used here, read from its lock after an Upstream check.
    @Published var newestEngineReadiness: NewestEngineReadiness? = nil
    @Published var isSwitchingEngine = false
    /// Why the last switch did not happen, shown calmly in the Newest engine row.
    @Published var newestEngineProblem: String? = nil
    lazy var upstreamChecker = UpstreamChecker()
    let upstreamCacheKey = "NXLibrary_UpstreamStatus"

    /// What the engine in use can read: title selection, extracted folders and NUP containers or programs.
    var engineSourceCapabilities: EngineSourceCapabilities {
        EngineSourceCapabilities(repo: URL(fileURLWithPath: nxnativePath))
    }

    // MARK: - Keys
    @Published var prodKeysPath: String = "" {
        didSet {
            if !prodKeysPath.isEmpty {
                AppData.preferences.set(prodKeysPath, forKey: AppViewModel.StorageKeys.savedProdKeysPath)
            }
        }
    }
    @Published var prodKeysSource: String = ""
    @Published var isProdKeysValid: Bool = false
    @Published var keySummary: KeySummary? = nil
    lazy var keyStore = KeyStore(directory: app.core.appendingPathComponent("keys"))

    // MARK: - Environment and the Metal gate
    @Published var environmentStatus: EnvironmentStatus? = nil
    @Published var compatibilityReport: CompatibilityReport? = nil
    @Published var isCheckingEnvironment = false
    var environmentCheckGeneration = UUID()
    @Published var allowUntestedToolchain: Bool = false {
        didSet {
            AppData.preferences.set(allowUntestedToolchain, forKey: AppViewModel.StorageKeys.allowUntestedToolchain)
        }
    }

    init(app: AppViewModel) {
        self.app = app
        // Restored here, where they live; an initializer does not run their `didSet`, as before.
        if AppData.preferences.object(forKey: AppViewModel.StorageKeys.allowUntestedToolchain) != nil {
            allowUntestedToolchain = AppData.preferences.bool(forKey: AppViewModel.StorageKeys.allowUntestedToolchain)
        }
        if let data = AppData.preferences.data(forKey: AppViewModel.StorageKeys.newestEngineChoice) {
            newestEngineChoice = try? JSONDecoder().decode(NewestEngineChoice.self, from: data)
        }
        if let data = AppData.preferences.data(forKey: upstreamCacheKey),
           let cached = try? JSONDecoder().decode(UpstreamStatus.self, from: data),
           cached.baseCommit == app.pinnedEngineCommit {
            upstreamState = .loaded(cached)
        }
    }

    // MARK: - Engine folder and upstream
    func checkUpstreamChangelog() {
        if case .checking = upstreamState { return }
        // Always against the tested pin, so the newest engine stays measurable from the engine Arcane tested.
        let base = app.pinnedEngineCommit
        upstreamState = .checking
        let checker = upstreamChecker
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let status = try await checker.check(from: base)
                self.upstreamState = .loaded(status)
                if let data = try? JSONEncoder().encode(status) {
                    AppData.preferences.set(data, forKey: self.upstreamCacheKey)
                }
                self.checkNewestEngineReadiness(status)
            } catch {
                self.upstreamState = .failed(Self.upstreamErrorMessage(error))
            }
        }
    }

    func openUpstreamCompare() {
        guard case .loaded(let status) = upstreamState else { return }
        NSWorkspace.shared.open(status.compareURL)
    }

    static func upstreamErrorMessage(_ error: Error) -> String {
        if let checkerError = error as? UpstreamCheckerError {
            return checkerError.localizedDescription
        }
        if let urlError = error as? URLError {
            return "Network error: \(urlError.localizedDescription)"
        }
        return error.localizedDescription
    }

    func selectNxnativeFolder() {
        guard !app.isBuilding, !app.isUpdatingApp else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select nxnative Folder"
        panel.message = "Choose the directory containing the nxnative scripts and tools."

        if panel.runModal() == .OK, let url = panel.url {
            guard EngineLocation.isEngine(url) else {
                app.alertMessage = "\(url.path) is not an nxnative checkout: it has no scripts/build_ipa_from_nsp.py and dm folder."
                SoundEffectService.shared.play(.error)
                return
            }
            // Remembered, so launch and every check use it; ~/nxnative itself needs nothing stored.
            if let saved = EngineLocation.savedValue(for: url, home: SystemDetector.shared.resolveRootDirectory()) {
                AppData.preferences.set(saved, forKey: AppViewModel.StorageKeys.savedEngineFolder)
            } else {
                AppData.preferences.removeObject(forKey: AppViewModel.StorageKeys.savedEngineFolder)
            }
            self.nxnativePath = url.path
            self.isNxnativeValid = true
            self.refreshCompatibility()
        }
    }

    // MARK: - Keys import
    func ensureKeysImported(customRyujinxDir: String? = nil) {
        let fm = FileManager.default
        if fm.fileExists(atPath: keyStore.keyURL.path) {
            do {
                let summary = try keyStore.validate(at: keyStore.keyURL)
                keySummary = summary
                isProdKeysValid = summary.hasHeaderKey
                prodKeysPath = keyStore.keyURL.path
                prodKeysSource = AppIdentity.name
            } catch {
                keySummary = nil
                isProdKeysValid = false
                prodKeysSource = "Invalid stored copy"
                app.logs.append(LogEntry(level: .error,
                                     message: L10n.format("Stored prod.keys is invalid: %@", [String(describing: error.localizedDescription)])))
            }
            return
        }
        let saved = AppData.preferences.string(forKey: AppViewModel.StorageKeys.savedProdKeysPath)
        let detected = SystemDetector.shared.detectProdKeys(additionalSearchDir: customRyujinxDir)
        let candidate = [saved, detected?.path].compactMap { $0 }.first {
            !$0.isEmpty && fm.fileExists(atPath: $0)
        }
        guard let candidate else {
            keySummary = nil
            isProdKeysValid = false
            prodKeysSource = "Not Found"
            prodKeysPath = ""
            return
        }
        importKeys(from: URL(fileURLWithPath: candidate))
    }

    func importKeys(from url: URL) {
        guard !app.isBuilding, !app.isUpdatingApp else {
            app.showSettingsNotice(title: L10n.text("Porting in progress"), message: L10n.text("Change keys after the porting finishes."))
            return
        }
        do {
            let summary = try keyStore.importKey(from: url)
            keySummary = summary
            isProdKeysValid = summary.hasHeaderKey
            prodKeysPath = keyStore.keyURL.path
            prodKeysSource = "Imported once"
            app.porting.refreshKeyCheck()
            if let folder = app.porting.selectedGameFolder { app.porting.scanGameFolder(folder) }
            app.lastError = nil
            app.logs.append(LogEntry(
                level: .success,
                message: L10n.format("prod.keys imported: header key present, %@ application key generations.", [String(describing: summary.applicationKeyGenerations.count)])
            ))
        } catch {
            keySummary = try? keyStore.validate(at: keyStore.keyURL)
            isProdKeysValid = keySummary?.hasHeaderKey == true
            prodKeysPath = isProdKeysValid ? keyStore.keyURL.path : ""
            app.lastError = error.localizedDescription
            app.showSettingsNotice(title: L10n.text("Keys not changed"), message: isProdKeysValid
                ? L10n.text("The key file could not be imported. Your previous copy is kept.")
                : L10n.text("The key file could not be imported. Choose a valid prod.keys file."))
            app.logs.append(LogEntry(level: .error,
                                 message: L10n.format("Could not import prod.keys: %@", [String(describing: error.localizedDescription)])))
        }
    }

    func selectProdKeysFile() {
        guard !app.isBuilding, !app.isUpdatingApp else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.prompt = "Select prod.keys"
        panel.message = "Choose your Nintendo Switch prod.keys file."

        if panel.runModal() == .OK, let url = panel.url {
            importKeys(from: url)
        }
    }

    // MARK: - Environment check and the gate
    /// The Python and PATH every engine process runs with (bundled runtime, else the venv).
    var engineToolchain: EngineToolchain {
        .resolve(runtime: .locate(), repo: URL(fileURLWithPath: self.nxnativePath))
    }

    func detectEnvironment(customRyujinxDir: String? = nil) {
        guard !app.isBuilding, !app.isUpdatingApp else { return }
        restoreBuildInputs(customRyujinxDir: customRyujinxDir)
        refreshCompatibility()
    }

    func restoreBuildInputs(customRyujinxDir: String? = nil, automatic: Bool = false) {
        let nxResult = SystemDetector.shared.detectNxnativeDirectory(
            saved: AppData.preferences.string(forKey: AppViewModel.StorageKeys.savedEngineFolder))
        self.nxnativePath = nxResult.path
        self.isNxnativeValid = nxResult.isValid
        if !automatic || !AppData.profile.isDevelopment { self.ensureKeysImported(customRyujinxDir: customRyujinxDir) }
    }

    /// With launch checks off, inspecting a build screen performs the check on demand.
    func prepareBuildEnvironmentIfNeeded() {
        if environmentStatus == nil, !isCheckingEnvironment { detectEnvironment() }
    }

    func refreshCompatibility() {
        guard !app.isBuilding, !app.isUpdatingApp else { return }
        let generation = UUID()
        environmentCheckGeneration = generation
        guard self.isNxnativeValid, !self.nxnativePath.isEmpty else {
            compatibilityReport = nil
            environmentStatus = nil
            isCheckingEnvironment = false
            return
        }
        isCheckingEnvironment = true
        environmentStatus = nil
        compatibilityReport = nil
        let repo = URL(fileURLWithPath: self.nxnativePath)
        let toolchain = engineToolchain
        let developerDir = resolvedDeveloperDir()
        let expected = self.activeEngineCommit
        let pinned = app.pinnedEngineCommit
        let choice = self.newestEngineChoice
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let environment = NXNativeEnvironment(repoURL: repo, toolchain: toolchain,
                                                  developerDir: developerDir)
            let status = environment.inspect()
            let includedInPin = choice.flatMap { NewestEngineSwitcher(repo: repo).isIncluded($0.commit, in: pinned) }
            let checker = CompatibilityChecker(repoURL: repo, toolchain: toolchain,
                                               developerDir: developerDir)
            let report = try? checker.check(expectedEngineCommit: expected)
            let currentCommit = report?.checks.first(where: { $0.id == "commit" })?.detail
                .components(separatedBy: ", expected").first?
                .replacingOccurrences(of: "current ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                guard let self, self.environmentCheckGeneration == generation,
                      self.nxnativePath == repo.path else { return }
                self.isCheckingEnvironment = false
                self.environmentStatus = status
                self.compatibilityReport = report
                self.currentEngineCommit = (currentCommit?.isEmpty == false) ? currentCommit : nil
                if let choice, !NewestEngine.keeps(choice, head: self.currentEngineCommit, pinned: pinned,
                                                    includedInPin: includedInPin) {
                    // The checkout moved (Setup, Back to tested, by hand) or an Arcane update tested this
                    // commit: the tested engine is in charge again.
                    self.forgetNewestEngine()
                    self.refreshCompatibility()
                    return
                }
                if let report, !report.ok {
                    let blocked = report.checks.filter { $0.status == .block }
                        .map { "\($0.title): \($0.detail)" }.joined(separator: " | ")
                    self.app.logs.append(LogEntry(level: .warning, message: L10n.format("Toolchain gate: %@", [String(describing: blocked)])))
                }
            }
        }
    }

    func resolvedDeveloperDir() -> URL { Self.resolveDeveloperDir() }

    /// Reads no state of the view model, so it can run off the main thread (it runs `xcode-select`).
    static func resolveDeveloperDir() -> URL {
        let fm = FileManager.default
        // An explicit DEVELOPER_DIR always wins.
        if let env = ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
           fm.fileExists(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        // Respect xcode-select when it points at a full Xcode, not the CLT.
        if let selected = try? SystemCommandRunner().run(
            URL(fileURLWithPath: "/usr/bin/xcode-select"), ["-p"],
            environment: nil, currentDirectory: nil
        ), selected.status == 0 {
            let path = selected.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.contains(".app/Contents/Developer"), fm.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // Prefer a normal Xcode install over the beta when xcode-select is CLT.
        let candidates = [
            "/Applications/Xcode.app/Contents/Developer",
            "/Applications/Xcode-beta.app/Contents/Developer",
            "/Library/Developer/CommandLineTools",
        ]
        for path in candidates where fm.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/Library/Developer/CommandLineTools")
    }

    var requiredMetalVersion: String? {
        let lock = URL(fileURLWithPath: self.nxnativePath)
            .appendingPathComponent("dm/gfx/tools/dmsh_chain.lock")
        guard let text = try? String(contentsOf: lock, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("metal_macosx\t") {
            guard let raw = line.split(separator: "\t").last.map(String.init) else { return nil }
            return MetalVersion.parse(raw) ?? raw
        }
        return nil
    }

    var installedMetalVersion: String? { environmentStatus?.metalVersion }

    var canPassToolchainGate: Bool {
        compatibilityReport?.ok == true || allowUntestedToolchain
    }

    /// A profile in `dm/games/<title ID>` is the engine's verified support for
    /// a title. Without one the engine builds from a provisional profile and
    /// may fail in the rewrite or at run time.
    func hasVerifiedEngineProfile(for game: PortedGame) -> Bool {
        hasVerifiedEngineProfile(titleId: game.titleId)
    }

    func hasVerifiedEngineProfile(titleId: String?) -> Bool {
        guard let titleId, !titleId.isEmpty else { return true }
        guard !self.nxnativePath.isEmpty else { return true }
        var isDirectory: ObjCBool = false
        let path = URL(fileURLWithPath: self.nxnativePath)
            .appendingPathComponent("dm/games/\(titleId.uppercased())").path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// What the compatibility gate says now; nil until the first check has run.
    var toolchainGateSummary: ToolchainGateCopy.Summary? {
        compatibilityReport.map { ToolchainGateCopy.summary(report: $0, overrideOn: allowUntestedToolchain, newest: self.usesNewestEngine) }
    }
}
