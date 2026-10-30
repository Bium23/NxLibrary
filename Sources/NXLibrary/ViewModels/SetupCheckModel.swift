import AppKit
import NXLibraryCore

/// Drives the Setup check: probes off the main thread, runs each card's action,
/// and Install all. The cards' states come from `SetupCheck`; an action in
/// progress shows over them until it ends (`SetupOverride`).
final class SetupCheckModel: ObservableObject {
    @Published private(set) var items: [SetupItem] = []
    @Published private(set) var installAllRunning = false
    @Published private(set) var installAllProgress: String?
    /// Cards that turned ready at the last probe, for the chip's pop.
    @Published private(set) var justReady: Set<SetupItemID> = []

    static let lastStatesKey = "NXLibrary_SetupLastStates"
    /// The engine's lock names the certified compiler; before there is an engine, this one.
    static let fallbackCertifiedMetal = "32023.921"

    private let viewModel: AppViewModel
    private let runner: CommandRunning
    private let queue = DispatchQueue(label: "nxlibrary.setup-check", qos: .userInitiated)
    private var facts: SetupFacts?
    private var overrides: [SetupItemID: SetupOverride] = [:]
    private var timer: Timer?
    private var probing = false

    init(viewModel: AppViewModel, runner: CommandRunning = SystemCommandRunner()) {
        self.viewModel = viewModel
        self.runner = runner
    }

    // MARK: - Checking

    private static func makeProbe(_ viewModel: AppViewModel, runner: CommandRunning) -> SetupProbe {
        SetupProbe(runner: runner, toolchain: viewModel.engineToolchain,
                   developerDir: viewModel.resolvedDeveloperDir(),
                   engineFolder: URL(fileURLWithPath: viewModel.nxnativePath),
                   pinnedCommit: viewModel.pinnedEngineCommit,
                   certifiedMetal: viewModel.requiredMetalVersion ?? fallbackCertifiedMetal,
                   allowUntested: viewModel.allowUntestedToolchain,
                   keyStore: viewModel.keyStore, libraryFolder: viewModel.libraryFolder)
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

    private func apply(_ facts: SetupFacts) {
        self.facts = facts
        let base = SetupCheck.items(from: facts)
        // A card that is ready now ends what was waiting on it ("Finish in Installer",
        // an old failure); a running action keeps its chip until it reports back.
        for item in base where item.state == .ready {
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
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stopRechecking() {
        timer?.invalidate()
        timer = nil
    }

    func rememberStates() {
        var states = UserDefaults.standard.dictionary(forKey: Self.lastStatesKey) as? [String: String] ?? [:]
        for item in items where item.state != .working {
            states[item.id.rawValue] = item.state.rawValue
        }
        UserDefaults.standard.set(states, forKey: Self.lastStatesKey)
    }

    /// At launch, after setup: opens the Setup check when something that was ready broke.
    static func checkAtLaunch(viewModel: AppViewModel) {
        guard viewModel.setupCompleted else { return }
        let probe = makeProbe(viewModel, runner: SystemCommandRunner())
        DispatchQueue.global(qos: .utility).async {
            let current = SetupCheck.items(from: probe.facts())
            DispatchQueue.main.async {
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

    /// The automatic actions Install all runs, in card order.
    var missingAutomatic: [SetupItemID] {
        items.compactMap { item in
            guard item.state != .working else { return nil }
            switch item.id {
            case .metal, .dotnet: return item.state == .missing ? item.id : nil
            case .engine:
                guard let facts else { return nil }
                return SetupActions.engineAction(for: facts.engine, pinned: facts.pinnedCommit) == .none ? nil : item.id
            default: return nil
            }
        }
    }

    func activate(_ id: SetupItemID) {
        guard let item = items.first(where: { $0.id == id }), item.state != .working else { return }
        if case .failed? = overrides[id] { overrides[id] = nil }
        switch id {
        case .xcode:
            if item.state == .missing {
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
        }
    }

    func installAll() {
        let ids = missingAutomatic
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
                                       message: "\(name): \(output.trimmingCharacters(in: .whitespacesAndNewlines))"))
        if result.status == 0 {
            setOverride(id, nil)
        } else {
            let last = output.split(separator: "\n").last.map(String.init) ?? "exit \(result.status)"
            setOverride(id, .failed(last))
        }
        refresh()
        completion(result.status == 0)
    }

    private func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        let env = viewModel.engineToolchain.environment(base: ProcessInfo.processInfo.environment,
                                                        developerDir: viewModel.resolvedDeveloperDir())
        return (try? runner.run(URL(fileURLWithPath: executable), arguments, environment: env, currentDirectory: nil))
            ?? CommandResult(status: -1, stdout: "", stderr: "\(executable) could not start")
    }

    private func installMetal(_ completion: @escaping (Bool) -> Void) {
        setOverride(.metal, .working("INSTALLING…"))
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.run("/usr/bin/xcodebuild", SetupActions.metalDownload)
            DispatchQueue.main.async { self.finish(.metal, result, "Metal compiler", completion) }
        }
    }

    private func fetchEngine(_ completion: @escaping (Bool) -> Void) {
        guard let facts else { completion(false); return }
        let action = SetupActions.engineAction(for: facts.engine, pinned: facts.pinnedCommit)
        let commands = SetupActions.gitCommands(for: action, folder: facts.engineFolder, pinned: facts.pinnedCommit)
        guard !commands.isEmpty else { completion(false); return }
        setOverride(.engine, .working(action == .clone ? "CLONING…" : "CHECKING OUT…"))
        queue.async { [weak self] in
            guard let self else { return }
            var result = CommandResult(status: 0, stdout: "", stderr: "")
            for command in commands {
                result = self.run("/usr/bin/git", command)
                if result.status != 0 { break }
            }
            DispatchQueue.main.async {
                self.viewModel.detectEnvironment()
                self.finish(.engine, result, "nxnative engine", completion)
            }
        }
    }

    private func installDotnet(_ completion: @escaping (Bool) -> Void) {
        setOverride(.dotnet, .working("DOWNLOADING…"))
        let fail: (String) -> Void = { [weak self] message in
            DispatchQueue.main.async {
                self?.viewModel.logs.append(LogEntry(level: .error, message: ".NET 10 SDK: \(message)"))
                self?.setOverride(.dotnet, .failed(message))
                completion(false)
            }
        }
        URLSession.shared.dataTask(with: DotnetRelease.metadataURL) { data, _, error in
            guard let data, error == nil else { return fail(error?.localizedDescription ?? "No answer from Microsoft.") }
            let package: DotnetPackage
            do { package = try DotnetRelease.latestSDKPackage(from: data) } catch { return fail(error.localizedDescription) }
            URLSession.shared.downloadTask(with: package.url) { [weak self] location, _, error in
                guard let location, error == nil else { return fail(error?.localizedDescription ?? "The download stopped.") }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NXLibrary-dotnet")
                let pkg = folder.appendingPathComponent(package.url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try? FileManager.default.removeItem(at: pkg)
                    try FileManager.default.moveItem(at: location, to: pkg)
                    guard try DotnetRelease.verify(file: pkg, sha512: package.sha512) else {
                        try? FileManager.default.removeItem(at: pkg)
                        return fail("The download does not match Microsoft's published hash, so it was deleted.")
                    }
                } catch {
                    return fail(error.localizedDescription)
                }
                DispatchQueue.main.async {
                    // macOS Installer asks for the password; NX Library waits for the SDK to appear.
                    NSWorkspace.shared.open(pkg)
                    self?.viewModel.logs.append(LogEntry(level: .info, message: ".NET \(package.version) SDK installer opened."))
                    self?.setOverride(.dotnet, .needsYou("FINISH IN INSTALLER"))
                    completion(true)
                }
            }.resume()
        }.resume()
    }
}
