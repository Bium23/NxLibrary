import Foundation

/// What a finished build says about a stage that ended with the engine's warning (`stage_end` with `warn`): the game
/// was built and plays, but without something that stage makes.
public enum BuildWarningCopy {
    public static func text(stage: String, summary: String?) -> String {
        if stage.localizedCaseInsensitiveContains("pipeline archive") {
            return "The pipeline archive could not be made, so the app was packed without one. "
                + "The game prepares its shaders the first time it needs them, so its first start can take longer. "
                + "The log has the reason; rebuilding tries again."
        }
        let detail = summary.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        let name = stage.prefix(1).uppercased() + stage.dropFirst()
        return "\(name) finished with a warning" + (detail.map { ": \($0)." } ?? ".") + " The log has the details."
    }
}
