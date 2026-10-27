import Foundation
import AppKit

public protocol AppLaunching {
    func open(_ url: URL, environment: [String: String],
              completion: @escaping (Bool, String?) -> Void)
}

public final class NSWorkspaceLauncher: AppLaunching {
    public init() {}

    public func open(_ url: URL, environment: [String: String],
                     completion: @escaping (Bool, String?) -> Void) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            completion(false, "The app bundle is missing: \(url.path)")
            return
        }
        var merged = ProcessInfo.processInfo.environment
        for (key, value) in environment { merged[key] = value }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.environment = merged
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                completion(false, error.localizedDescription)
            } else {
                completion(true, nil)
            }
        }
    }
}

public final class LaunchService {
    private let launcher: AppLaunching

    public init(launcher: AppLaunching = NSWorkspaceLauncher()) {
        self.launcher = launcher
    }

    public func writeEnvironment(
        settings: GameRuntimeConfig,
        titleId: String,
        baseDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/nxnative")
    ) throws {
        let dir = baseDirectory.appendingPathComponent(titleId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let envURL = dir.appendingPathComponent("env.txt")
        let existing = try? String(contentsOf: envURL, encoding: .utf8)
        try settings.mergedEnvContent(existing: existing).write(
            to: envURL, atomically: true, encoding: .utf8)
    }

    public func launch(appURL: URL, environment: [String: String] = [:],
                       completion: @escaping (Bool, String?) -> Void) {
        launcher.open(appURL, environment: environment, completion: completion)
    }

    public func saveDirectory(for titleId: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/nxnative")
            .appendingPathComponent(titleId).appendingPathComponent("save")
    }

    public func logURL(for titleId: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/nxnative")
            .appendingPathComponent("\(titleId).log")
    }
}
