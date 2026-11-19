import AppKit
import Foundation
import NXLibraryCore

/// The Switch Setup's state: the engine (folder, commit, upstream, newest engine), and from the next steps the keys,
/// the environment and the Metal gate. Settings → Setup and engine, the Setup check and Add Game observe it on their
/// own. It reaches the rest of Arcane only through `app`, the list of what the Porting module will ask of the base.
public final class SetupModel: ObservableObject {
    /// The coordinator: library, building state, alerts and the tested pin.
    unowned let app: AppViewModel

    // MARK: - Engine
    @Published public var nxnativePath: String = ""
    @Published public var isNxnativeValid: Bool = false
    @Published public var currentEngineCommit: String? = nil
    @Published public var upstreamState: UpstreamCheckState = .idle
    /// The newest nxnative the player chose in Settings → Setup and engine; nil while the tested engine is in use.
    @Published public internal(set) var newestEngineChoice: NewestEngineChoice? = nil {
        didSet {
            if let choice = newestEngineChoice, let data = try? JSONEncoder().encode(choice) {
                AppData.preferences.set(data, forKey: AppViewModel.StorageKeys.newestEngineChoice)
            } else {
                AppData.preferences.removeObject(forKey: AppViewModel.StorageKeys.newestEngineChoice)
            }
        }
    }
    /// Whether upstream main can be used here, read from its lock after an Upstream check.
    @Published public internal(set) var newestEngineReadiness: NewestEngineReadiness? = nil
    @Published public internal(set) var isSwitchingEngine = false
    /// Why the last switch did not happen, shown calmly in the Newest engine row.
    @Published public internal(set) var newestEngineProblem: String? = nil
    lazy var upstreamChecker = UpstreamChecker()
    let upstreamCacheKey = "NXLibrary_UpstreamStatus"

    init(app: AppViewModel) {
        self.app = app
        // Restored here, where they live; an initializer does not run their `didSet`, as before.
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
    public func checkUpstreamChangelog() {
        if case .checking = upstreamState { return }
        // Always against the tested pin, so the newest engine stays measurable from the engine NX Library tested.
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

    public func openUpstreamCompare() {
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

    public func selectNxnativeFolder() {
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
            app.refreshCompatibility()
        }
    }
}
