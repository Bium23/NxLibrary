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
    public private(set) var shaderETA: Double?
    /// Seconds the stages after the shaders took so far.
    public private(set) var finishingElapsed: Double = 0

    private var shaderStep: Int?
    private var finishingEnded = 0

    public init() {}

    public mutating func apply(_ event: BuildEvent) {
        guard phase != .done, phase != .failed else { return }
        switch event {
        case .stage(let k, let n, let name, _):
            step = k
            count = n
            if name == Self.shaderStageName {
                shaderStep = k
                phase = .shaders
            } else if let shaderStep, k > shaderStep {
                raise(to: Self.shaderShare)
                phase = .finishing
            }
        case .progress(let fraction, _, _, _, let eta):
            guard phase == .shaders else { return }
            raise(to: Self.shaderShare * min(max(fraction, 0), 1))
            shaderETA = eta
        case .stageEnd(let name, let ok, let elapsed, _):
            if name == Self.shaderStageName {
                raise(to: Self.shaderShare)
                phase = .finishing
            } else if phase == .finishing, ok {
                finishingEnded += 1
                finishingElapsed += elapsed ?? 0
                let stages = max(Self.expectedFinishingStages, count - (shaderStep ?? count))
                raise(to: Self.shaderShare + (1 - Self.shaderShare) * Double(finishingEnded) / Double(stages))
            }
        case .step, .say, .log:
            break
        }
    }

    public mutating func finish(success: Bool) {
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

    private mutating func raise(to value: Double) {
        overall = max(overall, min(value, 1))
    }
}
