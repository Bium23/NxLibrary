import Foundation

public enum BuildCommandBuilder {
    public static func make(
        repo: URL,
        python: URL,
        workspace: URL,
        keys: URL,
        output: URL,
        developerDir: URL,
        appName: String? = nil,
        bundleId: String? = nil,
        language: String? = nil,
        gpu: String? = nil,
        envFile: URL? = nil,
        allowUntestedToolchain: Bool = false,
        extraArguments: [String] = []
    ) -> BuildCommand {
        var args = [
            repo.appendingPathComponent("scripts/build_ipa_from_nsp.py").path,
            workspace.path,
            "-k", keys.path,
            "--platform", "mac-app",
            "--progress", "json",
            "-o", output.path,
            "--keep-extracted",
        ]
        if let appName, !appName.isEmpty { args += ["--app-name", appName] }
        if let bundleId, !bundleId.isEmpty { args += ["--bundle-id", bundleId] }
        if let language, !language.isEmpty { args += ["-l", language] }
        if let gpu, !gpu.isEmpty { args += ["--gpu", gpu] }
        if let envFile { args += ["--env-file", envFile.path] }
        // Since nxnative 4f24ce6 the engine itself refuses a non-certified
        // Metal compiler unless this flag is present. Keep it tied to the
        // app's explicit, persisted override.
        if allowUntestedToolchain { args.append("--allow-other-metal") }
        args += extraArguments

        var env = ProcessInfo.processInfo.environment
        let base = "/opt/homebrew/bin:/usr/local/bin:/usr/local/share/dotnet:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = base + ":" + (env["PATH"] ?? "")
        env["DEVELOPER_DIR"] = developerDir.path
        env["PYTHONUNBUFFERED"] = "1"
        return BuildCommand(executable: python, arguments: args,
                            environment: env, workingDirectory: repo)
    }
}
