import Foundation

/// What a finished build says about a stage that ended with the engine's warning (`stage_end` with `warn`): the game
/// was built and plays, but without something that stage makes.
public enum BuildWarningCopy {
    public static func text(stage: String, summary: String?) -> String {
        if stage.localizedCaseInsensitiveContains("pipeline archive") {
            return L10n.text("The pipeline archive could not be made, so the app was packed without one. ")
                + L10n.text("The game prepares its shaders the first time it needs them, so its first start can take longer. ")
                + L10n.text("The log has the reason; rebuilding tries again.")
        }
        let detail = summary.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        let name = stage.prefix(1).uppercased() + stage.dropFirst()
        return L10n.format("%@ finished with a warning", [String(describing: (name))]) + (detail.map { ": \($0)." } ?? ".") + L10n.text(" The log has the details.")
    }
}
