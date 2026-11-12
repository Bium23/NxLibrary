import AppKit
import NXLibraryCore

/// Copy diagnostics: what an issue needs, scrubbed by `DiagnosticsReport` (no key values, no
/// environment, the home folder as `~`).
extension AppViewModel {
    func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(DiagnosticsReport.markdown(diagnosticsInputs()), forType: .string)
        SoundEffectService.shared.play(.success)
    }

    private func diagnosticsInputs() -> DiagnosticsReport.Inputs {
        var i = DiagnosticsReport.Inputs()
        let info = Bundle.main.infoDictionary
        i.appVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let executable = Bundle.main.executableURL ?? Bundle.main.bundleURL
        i.buildDate = (try? executable.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.formatted(date: .abbreviated, time: .omitted)
        i.bundleID = Bundle.main.bundleIdentifier ?? "?"
        i.macOS = ProcessInfo.processInfo.operatingSystemVersionString
        i.chip = Self.sysctlString("machdep.cpu.brand_string") ?? "?"
        i.pinnedCommit = pinnedEngineCommit
        i.newestEngine = newestEngineChoice.map { "\($0.commit) (\(NewestEngineCopy.ahead($0.aheadBy)))" }
        i.engineHead = Self.engineHead(at: nxnativePath)
        i.xcodePath = resolvedDeveloperDir().path
        i.xcodeVersion = environmentStatus?.xcodeVersion
        i.metalFound = environmentStatus?.metalVersion
        i.metalCertified = ToolchainRequirements.current.metalAssets.keys.sorted().joined(separator: ", ")
        i.untestedOverride = allowUntestedToolchain
        let tools = environmentStatus?.tools ?? []
        i.python = engineToolchain.python.path
        i.setupRows = tools.map { ($0.name, $0.ok) }
        i.keysImported = FileManager.default.fileExists(atPath: keyStore.keyURL.path)
        i.hasHeaderKey = keySummary?.hasHeaderKey ?? false
        i.keyGenerations = keySummary?.applicationKeyGenerations.count ?? 0
        if let id = lastBuildGameID ?? frontGameID, let game = libraryGames.first(where: { $0.id == id }) {
            let failure = game.portingFailure.map { failure in
                failure == .cancelled ? "cancelled" : "failed (\(game.portingFailureReason?.kind.rawValue ?? "unknown"))"
            }
            i.game = (game.name, game.titleId, game.isPlayableLocally, game.lastBuild?.toolchainVerified,
                      failure ?? (game.lastBuild != nil ? "succeeded" : nil))
            i.cheats = cheatDiagnostics(for: game)
        }
        i.lastCommand = lastPortingCommand
        let logURL = buildLogURL ?? (lastBuildGameID.flatMap { id in libraryGames.first { $0.id == id } }
            .flatMap { logURL(for: $0) })
        if let logURL, let text = try? String(contentsOf: logURL, encoding: .utf8) {
            i.log = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(60).map(String.init)
        } else {
            i.log = logs.suffix(60).map(\.message)
        }
        return i
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// "<short hash> <subject>" of the checkout; nothing is fetched.
    private static func engineHead(at path: String) -> String? {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path + "/.git") else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path, "log", "-1", "--format=%h %s"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && out?.isEmpty == false ? out : nil
    }
}
