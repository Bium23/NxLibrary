import AppKit
import Foundation
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

/// A running porting: the engine's events, the stage timer, the end of the build and its errors.
extension PortingModel {
    func handleBuildEvent(_ event: BuildEvent) {
        app.portingProgress?.apply(event)
        switch event {
        case .stage(let k, let n, let name, let step):
            let now = Date()
            pipelinePollGeneration = UUID()
            isPollingPipelineArchive = false
            currentStageStartedAt = now
            self.currentStageName = name
            self.stageIndex = k
            self.totalStages = n
            for index in self.buildStages.indices
            where self.buildStages[index].id < k && self.buildStages[index].isRunning {
                self.buildStages[index].isRunning = false
                self.buildStages[index].isCompleted = true
            }
            if let index = self.buildStages.firstIndex(where: { $0.id == k }) {
                self.buildStages[index].isRunning = true
                self.buildStages[index].step = step ?? ""
                if self.buildStages[index].elapsedSeconds == nil {
                    self.buildStages[index].elapsedSeconds = 0
                }
            } else {
                self.buildStages.append(BuildStageItem(id: k, name: name,
                                                  step: step ?? "", isRunning: true,
                                                  elapsedSeconds: 0))
            }
            startStageElapsedTimerIfNeeded()
            if let step, !step.isEmpty { self.currentStepName = step }
            app.logs.append(LogEntry(level: .step, message: "[\(k)/\(n)] \(name)"))

        case .step(let step):
            self.currentStepName = step
            if let index = self.buildStages.firstIndex(where: { $0.id == self.stageIndex }) {
                self.buildStages[index].step = step
            }
            app.logs.append(LogEntry(level: .info, message: "↳ \(step)"))

        case .progress(let fraction, let done, let total, let unit, let eta, let elapsed):
            self.progressFraction = min(max(fraction, 0), 1)
            self.etaSeconds = eta
            if let elapsed,
               let index = self.buildStages.firstIndex(where: { $0.id == self.stageIndex && $0.isRunning }) {
                self.buildStages[index].elapsedSeconds = elapsed
                currentStageStartedAt = Date().addingTimeInterval(-elapsed)
            }
            if let done, let total, total > 0 {
                if let unit, !unit.isEmpty,
                   unit.lowercased() != "b", unit.lowercased() != "bytes" {
                    let percent = Int((min(1, max(0, done / total)) * 100).rounded(.down))
                    self.currentStepName = "\(Self.formatAmount(done)) / \(Self.formatAmount(total)) \(unit) (\(percent)%)"
                } else {
                    let doneText = AppViewModel.formatBytes(Int64(done))
                    let totalText = AppViewModel.formatBytes(Int64(total))
                    self.currentStepName = "\(doneText) / \(totalText)"
                }
            }

        case .stageEnd(let name, let ok, let elapsed, let summary, let warn):
            pipelinePollGeneration = UUID()
            isPollingPipelineArchive = false
            let warned = ok && warn
            if let index = self.buildStages.firstIndex(where: { $0.name == name })
                ?? self.buildStages.firstIndex(where: { $0.isRunning }) {
                self.buildStages[index].isRunning = false
                self.buildStages[index].isCompleted = ok
                self.buildStages[index].isFailed = !ok
                self.buildStages[index].hasWarning = warned
                self.buildStages[index].elapsedSeconds = elapsed ?? self.buildStages[index].elapsedSeconds
                self.buildStages[index].summary = summary
            }
            app.logs.append(LogEntry(
                level: warned ? .warning : ok ? .success : .error,
                message: "\(warned ? "⚠" : ok ? "✓" : "✗") \(name)\(summary.map { " — \($0)" } ?? "")"
            ))

        case .say(let message):
            app.logs.append(LogEntry(level: .info, message: message))

        case .log(let line):
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                app.logs.append(LogEntry(level: .info, message: trimmed))
            }
        }
    }

    func startStageElapsedTimerIfNeeded() {
        guard !self.isCancellingBuild, stageElapsedTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tickStageElapsed() }
        stageElapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopStageElapsedTimer() {
        pipelinePollGeneration = UUID()
        stageElapsedTimer?.invalidate()
        stageElapsedTimer = nil
        currentStageStartedAt = nil
        isPollingPipelineArchive = false
    }

    func tickStageElapsed() {
        guard app.isBuilding, !self.isCancellingBuild, let started = currentStageStartedAt,
              let index = self.buildStages.firstIndex(where: { $0.id == self.stageIndex && $0.isRunning }) else { return }
        let now = Date()
        let elapsed = max(0, now.timeIntervalSince(started))
        self.buildStages[index].elapsedSeconds = elapsed

        if self.currentStageName == PortingProgress.pipelineArchiveStageName,
           let cacheURL = currentBuildCacheURL,
           !isPollingPipelineArchive {
            isPollingPipelineArchive = true
            let logURL = cacheURL.appendingPathComponent("logs/pso_offline_mac.log")
            let generation = pipelinePollGeneration
            let architectures = self.buildStages[index].step.split(separator: " ").first?
                .split(separator: ",").map { $0.hasPrefix("applegpu_") ? String($0) : "applegpu_" + $0 } ?? []
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let event = PipelineArchiveProgress().poll(logURL: logURL, architectures: architectures,
                                                           stageStartedAt: started, now: Date())
                DispatchQueue.main.async {
                    guard let self, self.pipelinePollGeneration == generation else { return }
                    self.isPollingPipelineArchive = false
                    if let event, self.app.isBuilding, !self.isCancellingBuild, self.currentStageName == PortingProgress.pipelineArchiveStageName {
                        self.handleBuildEvent(event)
                    }
                }
            }
        }
    }

    func finishBuild(_ result: BuildResult, gameID: UUID,
                             finalApp: URL, tempDir: URL) {
        stopStageElapsedTimer()
        currentBuildCacheURL = nil
        app.portingProgress?.finish(success: result.success)
        app.isBuilding = false
        self.isCancellingBuild = false
        buildService = nil
        if result.heldApp == nil { try? FileManager.default.removeItem(at: tempDir) }
        buildTempDirectory = nil

        // Displayed state can retain a finished result for an explicit retry,
        // but is never serialized as a replacement catalog.
        if var game = app.libraryGames.first(where: { $0.id == gameID }) {
            let toolchain = activeBuildToolchain ?? ToolchainInfo(engineCommit: app.setup.activeEngineCommit, verified: false)
            let verified = toolchain.verified
            let record = BuildRecord(
                startedAt: buildStartedAt ?? Date(),
                endedAt: Date(),
                exitCode: result.exitCode,
                logPath: result.logURL.path,
                outputPath: result.success || result.installationFailed ? finalApp.path : nil,
                engineCommit: toolchain.engineCommit ?? app.setup.activeEngineCommit,
                metalVersion: toolchain.metalVersion,
                xcodeVersion: toolchain.xcodeVersion,
                toolchainVerified: verified,
                cancelled: result.cancelled
            )

            if result.success || result.installationFailed {
                _ = app.authorizeDevelopmentOperation(.build, game: game)
                _ = app.authorizeDevelopmentOperation(.icon, game: game)
                if let held = result.heldApp {
                    PendingInstaller.hold(PendingInstall(tempApp: held, finalApp: finalApp,
                                                         record: record, toolchain: toolchain), for: &game)
                    self.buildHeldGameID = game.id
                } else {
                    PendingInstaller.discard(&game)
                    game.recordInstalledBuild(record, toolchain: toolchain, at: finalApp,
                                              version: Self.appVersion(at: finalApp), date: Date())
                    // A new app has the build's icon: the player's goes back on (AppIconModel).
                    game.appIconPending = true
                }
                if let seconds = app.portingProgress?.finishingElapsed, seconds > 0 {
                    lastPortingFinishSeconds = seconds
                }
                self.progressFraction = 1
                self.currentStageName = result.heldApp == nil ? "Build completed" : PendingInstall.stageName
                if result.installationFailed {
                    self.currentStageName = "Installation failed"
                    self.buildState = .failed
                    self.buildSuccessPath = nil
                    self.buildError = "The build is ready. Retry installation."
                    self.portingFailureReason = nil
                    app.lastError = result.error
                    app.presentInstallFailure(for: game, error: result.error ?? "Installation failed.")
                } else {
                    self.buildState = .succeeded
                    self.buildSuccessPath = finalApp.path
                    self.buildError = nil
                    app.lastError = nil
                    app.logs.append(LogEntry(level: .success, message: result.heldApp == nil
                        ? L10n.format("Build succeeded: %@", [String(describing: finalApp.path)])
                        : L10n.format("Build succeeded while %@ is open: it installs when the game quits.", [String(describing: game.name)])))
                    SoundEffectService.shared.play(.launch)
                    notifyPortingEnded(game, success: true, held: result.heldApp != nil)
                }
            } else if result.cancelled {
                game.status = buildPreviousStatus
                    ?? (game.sources.isEmpty ? .builtSourcesMissing : .notBuilt)
                game.portingFailure = .cancelled
                game.portingFailureReason = nil
                self.buildState = .cancelled
                self.buildError = nil
                self.portingFailureReason = nil
                app.lastError = "Build cancelled."
                app.logs.append(LogEntry(level: .warning, message: L10n.text("Build cancelled.")))
            } else {
                let reason = PortingFailureClassifier.classify(
                    log: buildLogTail(result.logURL),
                    keysPath: SourceSelection.requiresKeys(game.sources) ? app.setup.keyStore.keyURL.path : "",
                    sourcePaths: game.sources.map(\.url.path)
                )
                let message = reason.what(game: game.name)
                game.status = .failed
                game.portingFailure = .failed
                game.portingFailureReason = reason
                self.buildState = .failed
                self.buildError = message
                self.portingFailureReason = reason
                app.lastError = message
                app.logs.append(LogEntry(level: .error,
                                     message: result.error ?? L10n.format("Build failed (exit code %@).", [String(describing: result.exitCode)])))
                app.logs.append(LogEntry(level: .error, message: "\(reason.title). \(message) \(reason.next)"))
                SoundEffectService.shared.play(.error)
                notifyPortingEnded(game, success: false)
            }

            let saved = app.persistBuildOutcome(game)
            if result.success && saved {
                if result.heldApp == nil { app.appIcon.appIconBuildLogs[gameID] = result.logURL }
                app.loadLibrary()
                app.appIcon.syncPendingAppIcons()
            }
        } else {
            self.buildState = result.success ? .succeeded
                : (result.cancelled ? .cancelled : .failed)
            if !result.success && !result.cancelled {
                self.buildError = result.error
                app.lastError = result.error
            }
        }

        buildStartedAt = nil
        buildPreviousStatus = nil
        app.currentBuildGameID = nil
        activeBuildToolchain = nil
    }

    func presentBuildError(_ error: Error) {
        let message = error.localizedDescription
        self.buildState = .failed
        self.buildError = message
        if case .keyCheck(let reason, _) = error as? NXLibraryError {
            self.portingFailureReason = reason
        } else {
            self.portingFailureReason = nil
        }
        app.lastError = message
        app.alertMessage = message
        app.logs.append(LogEntry(level: .error, message: message))
        SoundEffectService.shared.play(.error)
    }

    static func formatAmount(_ value: Double) -> String {
        if value.rounded() == value { return String(format: "%.0f", value) }
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    func detectedGame(from game: PortedGame) throws -> DetectedGame {
        let sources = game.sources.compactMap { item -> DetectedSource? in
            guard let titleId = item.titleId.flatMap({ UInt64($0, radix: 16) }) else {
                return nil
            }
            let version = item.versionString.flatMap {
                Int($0.lowercased().hasPrefix("v") ? String($0.dropFirst()) : $0)
            }
            return DetectedSource(url: item.url, kind: item.kind, titleId: titleId,
                                  version: version, sizeBytes: item.sizeBytes, layout: item.layout,
                                  requiresTitleSelection: item.requiresTitleSelection == true, nupProgram: item.nupProgram)
        }
        guard let titleId = game.titleId.flatMap({ UInt64($0, radix: 16) }) else {
            throw NXLibraryError.missingTitleId
        }
        let detected = DetectedGame(baseTitleId: titleId, name: game.name,
                                    base: sources.first(where: { $0.kind == .base }),
                                    updates: sources.filter { $0.kind == .update },
                                    dlcs: sources.filter { $0.kind == .dlc })
        guard detected.hasGame else { throw NXLibraryError.baseRequired }
        return detected
    }

    static func detectedSource(from file: GameFileItem) -> DetectedSource? {
        guard let titleId = file.titleId.flatMap({ UInt64($0, radix: 16) }) else {
            return nil
        }
        let version = file.versionString.flatMap {
            Int($0.lowercased().hasPrefix("v") ? String($0.dropFirst()) : $0)
        }
        return DetectedSource(url: file.url, kind: file.type, titleId: titleId,
                              version: version, sizeBytes: file.sizeBytes, layout: file.layout,
                              requiresTitleSelection: file.requiresTitleSelection == true, nupProgram: file.nupProgram)
    }

    static func appVersion(at app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return object["CFBundleShortVersionString"] as? String
    }
}
