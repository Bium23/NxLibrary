import Foundation

public enum BuildCommandBuilder {
    public static func make(
        repo: URL,
        toolchain: EngineToolchain,
        workspace: URL,
        keys: URL?,
        output: URL,
        developerDir: URL,
        appName: String? = nil,
        bundleId: String? = nil,
        language: String? = nil,
        gpu: String? = nil,
        envFile: URL? = nil,
        motion: Bool? = nil,
        romfsMode: String? = nil,
        titleId: String? = nil,
        packageVersion: String? = nil,
        allowUntestedToolchain: Bool = false,
        extraArguments: [String] = []
    ) -> BuildCommand {
        var args = [
            repo.appendingPathComponent("scripts/build_ipa_from_nsp.py").path,
            workspace.path,
            "--platform", "mac-app",
            "--progress", "json",
            "-o", output.path,
            "--keep-extracted",
        ]
        if let keys { args += ["-k", keys.path] }
        if let titleId { args += ["--title-id", titleId] }
        if let packageVersion { args += ["-p", packageVersion] }
        if let appName, !appName.isEmpty { args += ["--app-name", appName] }
        if let bundleId, !bundleId.isEmpty { args += ["--bundle-id", bundleId] }
        if let language, !language.isEmpty { args += ["-l", language] }
        if let gpu, !gpu.isEmpty { args += ["--gpu", gpu] }
        if let envFile { args += ["--env-file", envFile.path] }
        if let motion { args.append(motion ? "--motion" : "--no-motion") }
        if let romfsMode, !romfsMode.isEmpty { args += ["--romfs", romfsMode] }
        // Since nxnative 4f24ce6 the engine itself refuses a non-certified
        // Metal compiler unless this flag is present. Keep it tied to the
        // app's explicit, persisted override.
        if allowUntestedToolchain { args.append("--allow-other-metal") }
        args += extraArguments

        var env = toolchain.environment(base: ProcessInfo.processInfo.environment, developerDir: developerDir)
        env["PYTHONUNBUFFERED"] = "1"
        // The engine runs its shader workers at J (default: the core count). A Metal compile also waits on its
        // process start and file writes, so two more than the cores keeps them all busy: on an 8-core M1 Pro,
        // a 65,047-shader game went from 3.7 to 4.4 shaders a second (with the backdrop still). A J the user set wins.
        if env["J"] == nil { env["J"] = String(Self.shaderJobs(cores: ProcessInfo.processInfo.activeProcessorCount)) }
        return BuildCommand(executable: toolchain.python, arguments: args,
                            environment: env, workingDirectory: repo)
    }

    /// Shader workers for a Mac with this many cores.
    public static func shaderJobs(cores: Int) -> Int { max(2, cores) + 2 }
}
