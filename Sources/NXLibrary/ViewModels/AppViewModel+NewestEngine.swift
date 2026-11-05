import Foundation
import NXLibraryCore

/// Settings → Engine, Newest engine: the player may build with nxnative main before NX Library has tested it.
/// Never automatic (AGENTS.md): only these two actions move the checkout away from, or back to, the tested pin.
extension AppViewModel {
    /// The commit the gate expects and builds record: the player's newest engine, else the tested pin.
    public var activeEngineCommit: String { newestEngineChoice?.commit ?? pinnedEngineCommit }

    public var usesNewestEngine: Bool { newestEngineChoice != nil }

    /// Upstream main, when it is ahead of the tested pin and not already the engine in use.
    public var newestEngineOffer: UpstreamStatus? {
        guard case .loaded(let status) = upstreamState, status.newCommitsCount > 0,
              status.upstreamCommit != newestEngineChoice?.commit else { return nil }
        return status
    }

    /// Reads main's lock after an Upstream check, so the row can say in advance whether main needs a newer app.
    func checkNewestEngineReadiness(_ status: UpstreamStatus) {
        newestEngineReadiness = nil
        guard status.newCommitsCount > 0 else { return }
        let repo = URL(fileURLWithPath: nxnativePath)
        let pinned = pinnedEngineCommit
        Task { @MainActor [weak self] in
            let lock = await NewestEngine.fetchLock(commit: status.upstreamCommit)
            let tested = await Task.detached { NewestEngineSwitcher(repo: repo).lockMetal(at: pinned) }.value
                ?? ToolchainRequirements.current.fallbackMetal
            guard let self, case .loaded(let current) = self.upstreamState,
                  current.upstreamCommit == status.upstreamCommit else { return }
            self.newestEngineReadiness = NewestEngine.readiness(newestLock: lock, testedMetal: tested)
        }
    }

    public var canSwitchEngine: Bool {
        isNxnativeValid && !isSwitchingEngine && !isBuilding && !isUpdatingApp
    }

    /// Moves the engine to upstream main and turns the untested-toolchain override on.
    public func useNewestEngine() {
        guard canSwitchEngine, let status = newestEngineOffer else { return }
        if case .needsNewerApp = newestEngineReadiness { return }
        let repo = URL(fileURLWithPath: nxnativePath)
        let pinned = pinnedEngineCommit
        let commit = status.upstreamCommit
        let ahead = status.newCommitsCount
        isSwitchingEngine = true
        newestEngineProblem = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let switcher = NewestEngineSwitcher(repo: repo)
            let tested = switcher.lockMetal(at: pinned) ?? ToolchainRequirements.current.fallbackMetal
            let result = Result { try switcher.useNewest(commit: commit, testedMetal: tested) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSwitchingEngine = false
                switch result {
                case .success:
                    let turnedOn = !self.allowUntestedToolchain || self.newestEngineChoice?.turnedOnOverride == true
                    self.allowUntestedToolchain = true
                    self.newestEngineChoice = NewestEngineChoice(commit: commit, aheadBy: ahead, turnedOnOverride: turnedOn)
                    self.logs.append(LogEntry(level: .warning,
                        message: "Engine switched to nxnative main \(commit.prefix(7)) (\(NewestEngineCopy.ahead(ahead))); builds are recorded as untested."))
                case .failure(let error):
                    if case NewestEngineError.needsNewerApp(let metal) = error {
                        self.newestEngineReadiness = .needsNewerApp(metal: metal)
                    }
                    self.newestEngineProblem = error.localizedDescription
                    self.logs.append(LogEntry(level: .warning, message: "Newest engine: \(error.localizedDescription)"))
                }
                self.refreshCompatibility()
            }
        }
    }

    /// Returns the engine to the tested pin; the override goes back off if the choice turned it on.
    public func useTestedEngine() {
        guard canSwitchEngine, usesNewestEngine else { return }
        let repo = URL(fileURLWithPath: nxnativePath)
        let pinned = pinnedEngineCommit
        isSwitchingEngine = true
        newestEngineProblem = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try NewestEngineSwitcher(repo: repo).useTested(pinned: pinned) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSwitchingEngine = false
                switch result {
                case .success:
                    self.forgetNewestEngine()
                    self.logs.append(LogEntry(level: .info, message: "Engine back to the tested \(pinned.prefix(7))."))
                case .failure(let error):
                    self.newestEngineProblem = error.localizedDescription
                    self.logs.append(LogEntry(level: .warning, message: "Back to tested: \(error.localizedDescription)"))
                }
                self.refreshCompatibility()
            }
        }
    }

    /// Drops the choice once the checkout is no longer at it.
    func forgetNewestEngine() {
        guard let choice = newestEngineChoice else { return }
        newestEngineChoice = nil
        if choice.turnedOnOverride { allowUntestedToolchain = false }
    }
}
