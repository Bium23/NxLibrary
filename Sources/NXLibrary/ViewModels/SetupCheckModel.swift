import AppKit
import NXLibraryCore

/// Drives the Setup check: probes off the main thread, runs each card's action
/// with live progress, and fixes what it can by itself each time the screen
/// opens. The cards' states come from `SetupCheck`; an action in progress shows
/// over them until it ends (`SetupOverride`). AppViewModel owns one, so an
/// install keeps going while the screen is closed.
final class SetupCheckModel: ObservableObject {
    @Published private(set) var items: [SetupItem] = []
    @Published private(set) var installAllRunning = false
    @Published private(set) var installAllProgress: String?
    /// Cards that turned ready at the last probe, for the chip's pop.
    @Published private(set) var justReady: Set<SetupItemID> = []

    static let lastStatesKey = "NXLibrary_SetupLastStates"
    static let requirements = ToolchainRequirements.current

    private unowned let viewModel: AppViewModel
    private let runner = SystemCommandRunner()
    private let queue = DispatchQueue(label: "nxlibrary.setup-check", qos: .userInitiated)
    private var facts: SetupFacts?
    private var overrides: [SetupItemID: SetupOverride] = [:]
    private var timer: Timer?
    private var probing = false
    private var dotnetPackage: DotnetPackage?
    private var dotnetLookup = false
    private var dotnetObservation: NSKeyValueObservation?

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Checking

    private static func makeProbe(_ viewModel: AppViewModel, runner: CommandRunning) -> SetupProbe {
        SetupProbe(runner: runner, toolchain: viewModel.engineToolchain,
                   developerDir: viewModel.resolvedDeveloperDir(),
                   engineFolder: URL(fileURLWithPath: viewModel.nxnativePath),
                   pinnedCommit: viewModel.pinnedEngineCommit,
                   certifiedMetal: viewModel.requiredMetalVersion ?? requirements.fallbackMetal,
                   allowUntested: viewModel.allowUntestedToolchain,
                   keyStore: viewModel.keyStore, libraryFolder: viewModel.libraryFolder,
                   sourcesFolder: viewModel.gameFilesFolder,
                   libraryNeedsConfirmation: viewModel.requiresGameAppsFolderChoice,
                   newestEngine: viewModel.newestEngineChoice)
    }

    func refresh() {
        guard !probing else { return }
        probing = true
        let probe = Self.makeProbe(viewModel, runner: runner)
        queue.async { [weak self] in
            let facts = probe.facts()
            DispatchQueue.main.async {
                self?.probing = false
                self?.apply(facts)
            }
        }
    }

    private func apply(_ probed: SetupFacts) {
        var facts = probed
        facts.dotnetLatest = dotnetPackage?.version
        self.facts = facts
        let base = SetupCheck.items(from: facts)
        // A card that is ready now ends what was waiting on it ("Finish in Installer",
        // an old failure); a running action keeps its chip until it reports back.
        for item in base where item.state == .ready && item.actionTitle == nil {
            if case .working? = overrides[item.id] { continue }
            overrides[item.id] = nil
        }
        let updated = SetupCheck.applying(overrides, to: base)
        let wasReady = Set(items.filter { $0.state == .ready }.map(\.id))
        let newlyReady = Set(updated.filter { $0.state == .ready }.map(\.id)).subtracting(wasReady)
        if !items.isEmpty, !newlyReady.isEmpty { SoundEffectService.shared.play(.focus) }
        justReady = items.isEmpty ? [] : newlyReady
        items = updated
    }

    func startRechecking() {
        lookUpDotnet()
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stopRechecking() {
        timer?.invalidate()
        timer = nil
    }

    /// Microsoft's newest SDK of the required major, once per session; offline it stays unknown.
    private func lookUpDotnet() {
        guard dotnetPackage == nil, !dotnetLookup else { return }
        dotnetLookup = true
        URLSession.shared.dataTask(with: DotnetRelease.metadataURL) { [weak self] data, _, _ in
            let package = data.flatMap { try? DotnetRelease.latestSDKPackage(from: $0) }
            DispatchQueue.main.async {
                self?.dotnetLookup = false
                guard let package, package.version.hasPrefix("\(Self.requirements.dotnetMajor).") else { return }
                self?.dotnetPackage = package
                self?.refresh()
            }
        }.resume()
    }

    func rememberStates() {
        var states = UserDefaults.standard.dictionary(forKey: Self.lastStatesKey) as? [String: String] ?? [:]
        for item in items where item.state != .working {
            states[item.id.rawValue] = item.state.rawValue
        }
        UserDefaults.standard.set(states, forKey: Self.lastStatesKey)
    }

    /// At launch, after setup: opens the Setup check when something that was ready
    /// broke or fell out of step with the engine; opening it starts the fix.
    static func checkAtLaunch(viewModel: AppViewModel) {
        guard viewModel.setupCompleted else { return }
        let enginePath = viewModel.nxnativePath
        let probe = makeProbe(viewModel, runner: SystemCommandRunner())
        DispatchQueue.global(qos: .utility).async {
            let current = SetupCheck.items(from: probe.facts())
            DispatchQueue.main.async {
                guard !viewModel.isBuilding, !viewModel.isUpdatingApp,
                      viewModel.nxnativePath == enginePath else { return }
                let stored = UserDefaults.standard.dictionary(forKey: lastStatesKey) as? [String: String] ?? [:]
                var previous: [SetupItemID: SetupState] = [:]
                for (key, value) in stored {
                    if let id = SetupItemID(rawValue: key), let state = SetupState(rawValue: value) { previous[id] = state }
                }
                if SetupCheck.shouldReopen(previous: previous, current: current) {
                    viewModel.showSetupCheck = true
                } else {
                    UserDefaults.standard.set(
                        Dictionary(uniqueKeysWithValues: current.map { ($0.id.rawValue, $0.state.rawValue) }),
                        forKey: lastStatesKey)
                }
            }
        }
    }

    // MARK: - Actions

    /// What Install all runs, in card order, updates included.
    var missingAutomatic: [SetupItemID] {
        SetupCheck.automatic(items, includeUpdates: true)
    }

    func activate(_ id: SetupItemID) {
        guard let item = items.first(where: { $0.id == id }), item.state != .working else { return }
        if case .failed? = overrides[id] { overrides[id] = nil }
        switch id {
        case .xcode:
            if item.state == .missing || item.chip == "UPDATE XCODE" {
                NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/id497799835")!)
            } else if item.state == .needsYou {
                let app = viewModel.resolvedDeveloperDir().deletingLastPathComponent().deletingLastPathComponent()
                NSWorkspace.shared.open(app)
            }
        case .metal, .dotnet, .engine:
            guard item.actionTitle != nil || item.state == .needsYou else { return }
            perform(id) { _ in }
        case .runtime:
            break
        case .keys:
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Import"
            panel.message = "Choose your prod.keys file. It stays on this Mac."
            if panel.runModal() == .OK, let url = panel.url {
                viewModel.importKeys(from: url)
            }
            refresh()
        case .library:
            viewModel.selectLibraryFolder()
            refresh()
        case .sources:
            viewModel.selectGameFolder()
            refresh()
        }
    }

    func installAll(_ ids: [SetupItemID]? = nil) {
        let ids = ids ?? missingAutomatic
        guard !ids.isEmpty, !installAllRunning else { return }
        installAllRunning = true
        step(ids, 0)
    }

    private func step(_ ids: [SetupItemID], _ index: Int) {
        guard index < ids.count else {
            installAllRunning = false
            installAllProgress = nil
            refresh()
            return
        }
        installAllProgress = "Installing \(index + 1) of \(ids.count)…"
        // Each action ends on its own card; a failure never stops the next one.
        perform(ids[index]) { [weak self] _ in self?.step(ids, index + 1) }
    }

    private func setOverride(_ id: SetupItemID, _ override: SetupOverride?) {
        overrides[id] = override
        if let facts { items = SetupCheck.applying(overrides, to: SetupCheck.items(from: facts)) }
    }

    /// From any thread: moves a working card's bar, skipping changes too small to see.
    private func report(_ id: SetupItemID, _ chip: String, _ progress: InstallProgress) {
        DispatchQueue.main.async { [weak self] in
            guard let self, case .working(let oldChip, let old, _)? = self.overrides[id] else { return }
            if oldChip == chip, let old, let new = progress.fraction, abs(new - old) < 0.005 { return }
            self.setOverride(id, .working(chip, progress: progress.fraction ?? old, detail: progress.label))
        }
    }

    private func perform(_ id: SetupItemID, completion: @escaping (Bool) -> Void) {
        switch id {
        case .metal: installMetal(completion)
        case .dotnet: installDotnet(completion)
        case .engine: fetchEngine(completion)
        default: completion(false)
        }
    }

    private func finish(_ id: SetupItemID, _ result: CommandResult, _ name: String,
                        _ completion: @escaping (Bool) -> Void) {
        let output = [result.stdout, result.stderr].joined(separator: "\n")
        viewModel.logs.append(LogEntry(level: result.status == 0 ? .success : .error,
                                       message: "\(name): \(output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(2000))"))
        if result.status == 0 {
            setOverride(id, nil)
        } else {
            let last = output.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).last.map(String.init) ?? "exit \(result.status)"
            setOverride(id, .failed(last))
        }
        refresh()
        completion(result.status == 0)
    }

    private var environment: [String: String] {
        viewModel.engineToolchain.environment(base: ProcessInfo.processInfo.environment,
                                              developerDir: viewModel.resolvedDeveloperDir())
    }

    private func stream(_ executable: String, _ arguments: [String], env: [String: String],
                        onLine: @escaping (String) -> Void) -> CommandResult {
        (try? runner.stream(URL(fileURLWithPath: executable), arguments, environment: env,
                            currentDirectory: nil, onLine: onLine))
            ?? CommandResult(status: -1, stdout: "", stderr: "\(executable) could not start")
    }

    /// The certified compiler first, by Apple's asset build; with no Metal at all
    /// and no certified asset on offer, whatever matches this Xcode. Nothing is deleted.
    private func installMetal(_ completion: @escaping (Bool) -> Void) {
        guard let facts else { completion(false); return }
        let certified = facts.certifiedMetal
        let hadMetal = facts.metalVersion != nil
        let allowUntested = facts.allowUntested
        let pinned = Self.requirements.metalDownload(for: certified)
        let chip = "DOWNLOADING…"
        setOverride(.metal, .working(chip, detail: "Asking Apple for Metal \(certified)…"))
        let env = environment
        queue.async { [weak self] in
            guard let self else { return }
            let onLine: (String) -> Void = { line in
                if let fraction = InstallProgress.percent(line) {
                    self.report(.metal, chip, InstallProgress(fraction: fraction, label: line.trimmingCharacters(in: .whitespaces)))
                }
            }
            var result = pinned.map { self.stream("/usr/bin/xcodebuild", $0, env: env, onLine: onLine) }
            if result?.status != 0, !hadMetal {
                result = self.stream("/usr/bin/xcodebuild", ToolchainRequirements.anyMetalDownload, env: env, onLine: onLine)
            }
            var final = result ?? CommandResult(status: 1, stdout: "", stderr: "Apple offers no Metal \(certified) for this Xcode.")
            if final.status == 0, !allowUntested {
                let now = (try? self.runner.run(URL(fileURLWithPath: "/usr/bin/xcrun"), ["metal", "--version"],
                                                environment: env, currentDirectory: nil))
                    .flatMap { MetalVersion.parse($0.stdout) }
                if let now, now != certified {
                    final = CommandResult(status: 1, stdout: final.stdout,
                                          stderr: "This Xcode uses Metal \(now); builds wait for an NX Library update tested with it.")
                }
            }
            DispatchQueue.main.async {
                self.viewModel.detectEnvironment()
                self.finish(.metal, final, "Metal compiler", completion)
            }
        }
    }

    private func fetchEngine(_ completion: @escaping (Bool) -> Void) {
        guard let facts else { completion(false); return }
        if case .checkout(let head, false) = facts.engine, head == facts.newestEngine?.commit {
            backToTestedEngine(completion)
            return
        }
        let action = SetupActions.engineAction(for: facts.engine, pinned: facts.pinnedCommit,
                                               newest: facts.newestEngine?.commit)
        let commands = SetupActions.gitCommands(for: action, folder: facts.engineFolder, pinned: facts.pinnedCommit)
        guard !commands.isEmpty else { completion(false); return }
        let chip = action == .clone ? "CLONING…" : "UPDATING…"
        setOverride(.engine, .working(chip, progress: 0, detail: "Connecting to GitHub…"))
        let env = environment
        queue.async { [weak self] in
            guard let self else { return }
            var result = CommandResult(status: 0, stdout: "", stderr: "")
            for command in commands {
                result = self.stream("/usr/bin/git", command, env: env) { line in
                    if let progress = InstallProgress.git(line) { self.report(.engine, chip, progress) }
                }
                if result.status != 0 { break }
            }
            DispatchQueue.main.async {
                self.viewModel.detectEnvironment()
                self.finish(.engine, result, "nxnative engine", completion)
            }
        }
    }

    /// The newest engine's card: A returns to the tested engine, the same action as Settings → Engine.
    private func backToTestedEngine(_ completion: @escaping (Bool) -> Void) {
        setOverride(.engine, .working("SWITCHING…", detail: "Returning to the tested engine…"))
        viewModel.useTestedEngine()
        waitForEngineSwitch(completion)
    }

    private func waitForEngineSwitch(_ completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            if self.viewModel.isSwitchingEngine { self.waitForEngineSwitch(completion); return }
            if let problem = self.viewModel.newestEngineProblem {
                self.setOverride(.engine, .failed(problem))
                completion(false)
            } else {
                self.setOverride(.engine, nil)
                self.refresh()
                completion(true)
            }
        }
    }

    private func installDotnet(_ completion: @escaping (Bool) -> Void) {
        let session = URLSession(configuration: .ephemeral, delegate: DotnetDownloadPolicy(), delegateQueue: nil)
        let chip = "DOWNLOADING…"
        setOverride(.dotnet, .working(chip, detail: "Asking Microsoft for the newest .NET \(Self.requirements.dotnetMajor) SDK…"))
        let fail: (String) -> Void = { [weak self] message in
            session.finishTasksAndInvalidate()
            DispatchQueue.main.async {
                self?.dotnetObservation = nil
                self?.viewModel.logs.append(LogEntry(level: .error, message: ".NET SDK: \(message)"))
                self?.setOverride(.dotnet, .failed(message))
                completion(false)
            }
        }
        let download: (DotnetPackage) -> Void = { [weak self] package in
            let task = session.downloadTask(with: package.url) { location, response, error in
                defer { session.finishTasksAndInvalidate() }
                guard let location, error == nil, let http = response as? HTTPURLResponse,
                      http.statusCode == 200, let finalURL = http.url, DotnetRelease.trustedDownloadURL(finalURL)
                else { return fail(error?.localizedDescription ?? "The download stopped.") }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NXLibrary-dotnet")
                let pkg = folder.appendingPathComponent(package.url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try? FileManager.default.removeItem(at: pkg)
                    try FileManager.default.moveItem(at: location, to: pkg)
                    self?.report(.dotnet, "CHECKING…", InstallProgress(fraction: 1, label: "Checking Microsoft's hash…"))
                    guard try DotnetRelease.verify(file: pkg, sha512: package.sha512) else {
                        try? FileManager.default.removeItem(at: pkg)
                        return fail("The download does not match Microsoft's published hash, so it was deleted.")
                    }
                } catch {
                    return fail(error.localizedDescription)
                }
                DispatchQueue.main.async {
                    self?.dotnetObservation = nil
                    // macOS Installer asks for the password; NX Library waits for the SDK to appear.
                    NSWorkspace.shared.open(pkg)
                    self?.viewModel.logs.append(LogEntry(level: .info, message: ".NET \(package.version) SDK installer opened."))
                    self?.setOverride(.dotnet, .needsYou("FINISH IN INSTALLER"))
                    completion(true)
                }
            }
            self?.dotnetObservation = task.progress.observe(\.fractionCompleted) { progress, _ in
                self?.report(.dotnet, chip, InstallProgress.bytes(done: progress.completedUnitCount,
                                                                  total: progress.totalUnitCount))
            }
            task.resume()
        }
        if let package = dotnetPackage { download(package); return }
        session.dataTask(with: DotnetRelease.metadataURL) { data, response, error in
            guard let data, error == nil, let http = response as? HTTPURLResponse,
                  http.statusCode == 200, let finalURL = http.url, DotnetRelease.trustedDownloadURL(finalURL)
            else { return fail(error?.localizedDescription ?? "No answer from Microsoft.") }
            do { download(try DotnetRelease.latestSDKPackage(from: data)) } catch { fail(error.localizedDescription) }
        }.resume()
    }
}
