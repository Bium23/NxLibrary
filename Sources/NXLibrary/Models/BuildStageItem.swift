import Foundation

struct BuildStageItem: Identifiable, Equatable {
    let id: Int // 1-based stage index
    let name: String
    var step: String
    var isRunning: Bool
    var isCompleted: Bool
    var isFailed: Bool
    var elapsedSeconds: Double?
    var summary: String?
    /// Finished, but without what it makes (the engine's `warn`).
    var hasWarning = false

    init(
        id: Int,
        name: String,
        step: String = "",
        isRunning: Bool = true,
        isCompleted: Bool = false,
        isFailed: Bool = false,
        elapsedSeconds: Double? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.name = name
        self.step = step
        self.isRunning = isRunning
        self.isCompleted = isCompleted
        self.isFailed = isFailed
        self.elapsedSeconds = elapsedSeconds
        self.summary = summary
    }
}
