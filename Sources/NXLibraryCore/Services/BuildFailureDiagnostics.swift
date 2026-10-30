import Foundation

/// Turns the engine's raw build log into a message that names the actual
/// limitation instead of only "Build exited with status 1".
public enum BuildFailureDiagnostics {
    public static func message(log: String, gameName: String, fallback: String? = nil) -> String {
        guard log.contains("provisional game profile") || log.contains("no game profile for") else {
            return fallback ?? "Build failed."
        }

        if log.contains("Direct RomFS image builds require Python 3.12") {
            return "\(gameName) could not build because its Python is older than 3.12. The current engine needs Python 3.12+ for RomFS image builds. NX Library carries its own Python 3.14: reinstall the app, or in a developer build recreate ~/nxnative/.venv with Python 3.14, then retry. Sources, saves and existing apps were not changed."
        }

        let rewriteFailed = log.contains("patch_nso.py")
            || log.contains("AssertionError")
            || log.contains("jump table")
        if rewriteFailed {
            let at = jumpTableAddress(in: log).map { " at 0x\($0)" } ?? ""
            return "\(gameName) has no verified nxnative game profile. The provisional code rewrite failed\(at); this title is not supported by the pinned engine yet. Sources and existing apps were not changed. Open the build log for the engine traceback."
        }

        return "\(gameName) has no verified nxnative game profile. The provisional build failed; this title may not be supported by the pinned engine. Sources and existing apps were not changed. Open the build log for details."
    }

    public static func jumpTableAddress(in log: String) -> String? {
        guard let range = log.range(of: "jump table ", options: .backwards) else { return nil }
        let hex = log[range.upperBound...].prefix { $0.isHexDigit }
        return hex.isEmpty ? nil : String(hex)
    }
}
