import Foundation

/// One porting as the home shows it: the engine's events folded into a phase and
/// one overall fraction. The shaders count to 90%; the stages after them share
/// the last 10%, each share added when its stage ends. `overall` never moves back.
public struct PortingProgress: Equatable {
    public enum Phase: Equatable {
        /// Short stages before the shaders: only "step of count" is known.
        case preparing
        case shaders
        /// The stages after the shaders (Mac host, Pipeline archive, Mac app today).
        case finishing
        case done
        case failed
    }

    public static let shaderStageName = "Mac shaders"
    public static let shaderShare = 0.9
    /// The stages after the shaders when the engine has not counted them yet.
    public static let expectedFinishingStages = 3

    public private(set) var phase: Phase = .preparing
    public private(set) var overall: Double = 0
    /// The engine's "k of n"; n grows as the engine learns its stages.
    public private(set) var step = 0
    public private(set) var count = 0
    /// The engine's current stage and its step ("Mac shaders", "translating").
    public private(set) var stageName = ""
    public private(set) var stepName = ""
    public private(set) var shaderETA: Double?
    /// Cache maintenance has no count or reliable ETA; show its activity instead.
    public private(set) var isCleaningShaderCache = false
    /// Seconds the stages after the shaders took so far.
    public private(set) var finishingElapsed: Double = 0

    private var shaderStep: Int?
    private var finishingEnded = 0

    public init() {}

    public mutating func apply(_ event: BuildEvent) {
        guard phase != .done, phase != .failed else { return }
        switch event {
        case .stage(let k, let n, let name, let stepTitle):
            isCleaningShaderCache = false
            step = k
            count = n
            stageName = name
            stepName = stepTitle ?? ""
            if name == Self.shaderStageName {
                shaderStep = k
            } else if let shaderStep, k > shaderStep {
                raise(to: Self.shaderShare)
                phase = .finishing
            }
        case .step(let title):
            isCleaningShaderCache = false
            stepName = title
        case .progress(let fraction, let done, _, _, let eta):
            guard countsAsShaders(hasCount: done != nil) else { return }
            phase = .shaders
            raise(to: Self.shaderShare * min(max(fraction, 0), 1))
            shaderETA = eta
        case .stageEnd(let name, let ok, let elapsed, _, _):
            if name == Self.shaderStageName {
                raise(to: Self.shaderShare)
                phase = .finishing
            } else if phase == .finishing, ok {
                finishingEnded += 1
                finishingElapsed += elapsed ?? 0
                let stages = max(Self.expectedFinishingStages, count - (shaderStep ?? count))
                raise(to: Self.shaderShare + (1 - Self.shaderShare) * Double(finishingEnded) / Double(stages))
            }
        case .say(let message):
            if message.contains("removing the shader cache of other chain versions") {
                isCleaningShaderCache = true
            } else if message.contains("removed old shader cache entries:") {
                isCleaningShaderCache = false
            }
        case .log:
            break
        }
    }

    public mutating func finish(success: Bool) {
        isCleaningShaderCache = false
        if success {
            overall = 1
            phase = .done
        } else {
            phase = .failed
        }
    }

    /// Seconds the stages after the shaders took in a porting log; nil without a shader stage.
    public static func finishingSeconds(inLog text: String) -> Double? {
        var progress = PortingProgress()
        for line in text.split(whereSeparator: \.isNewline) {
            if let event = BuildEventParser.parse(String(line)) { progress.apply(event) }
        }
        guard progress.shaderStep != nil, progress.finishingEnded > 0 else { return nil }
        return progress.finishingElapsed
    }

    /// Inside the shader stage, only compiling (and its finishing tail) is the
    /// percentage: cache check and translating take seconds and restart their own
    /// fraction. An engine that names no step counts once it reports a count.
    private func countsAsShaders(hasCount: Bool) -> Bool {
        guard stageName == Self.shaderStageName, phase == .preparing || phase == .shaders else { return false }
        let step = stepName.lowercased()
        if step.isEmpty { return hasCount }
        return step.contains("compil") || step.contains("finishing")
    }

    private mutating func raise(to value: Double) {
        overall = max(overall, min(value, 1))
    }
}
