import Foundation
import NXLibraryCore

/// What the Porting screens (Add Game and its Porting step) show of a build: the wizard step, the live stages and
/// how the last porting ended. Add Game observes it on its own, so a stage or progress change redraws only those
/// screens. What the rest of Arcane reads of a porting stays on `AppViewModel`: `isBuilding`, `currentBuildGameID`
/// and `portingProgress` (the home's tile).
public final class PortingModel: ObservableObject {
    // MARK: - Wizard
    @Published public var buildWizardStep: Int = 1 // 1: Select Game, 2: Configure & Output, 3: Porting
    @Published public var showLiveLogsInBuild: Bool = true

    // MARK: - Live build
    @Published public var buildState: BuildState = .idle
    @Published public var isCancellingBuild: Bool = false
    @Published public var currentStageName: String = ""
    @Published public var currentStepName: String = ""
    @Published public var stageIndex: Int = 0
    @Published public var totalStages: Int = 0
    @Published public var progressFraction: Double = 0.0
    @Published public var etaSeconds: Double? = nil
    @Published public var buildStages: [BuildStageItem] = []

    // MARK: - Outcome
    @Published public var buildError: String? = nil
    /// Why the porting on the Porting step failed, when recognised; nil otherwise.
    @Published public var portingFailureReason: PortingFailureReason? = nil
    @Published public var buildSuccessPath: String? = nil
    /// The game whose finished build waits for it to quit (`PendingInstall`).
    @Published var buildHeldGameID: UUID? = nil

    public init() {}
}
