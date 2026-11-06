import Foundation

/// How the last porting of a game ended when it did not succeed. Saved with the
/// game, so the home still shows it after a relaunch; a successful porting clears it.
public enum PortingFailure: String, Codable, Equatable {
    case failed
    case cancelled
}

/// The small time line under the porting pills.
public enum PortingETA {
    /// Shaders: the engine's ETA plus what the final stages took last time on this
    /// Mac, or the shaders' part alone. Finishing: what is left of last time.
    /// Nothing before the shaders.
    public static func text(_ progress: PortingProgress, lastFinishingSeconds: Double?) -> String? {
        if progress.isUpdatingShaderCache { return "Updating shader cache" }
        switch progress.phase {
        case .shaders:
            guard let eta = progress.shaderETA else { return nil }
            if let last = lastFinishingSeconds { return "About \(minutes(eta + last)) min left" }
            return "Shaders: about \(minutes(eta)) min"
        case .finishing:
            guard let last = lastFinishingSeconds else { return "Finishing up" }
            return "About \(minutes(max(0, last - progress.finishingElapsed))) min left"
        case .preparing, .done, .failed:
            return nil
        }
    }

    static func minutes(_ seconds: Double) -> Int {
        max(1, Int((seconds / 60).rounded()))
    }
}

/// What a game's art tile shows.
public enum PortingTileLook: Equatable {
    case normal
    /// Black and white, blurred, a thin "step/count" bar with the stage and its step in small type.
    case preparing(step: Int, count: Int, title: String, detail: String)
    /// Colour risen to this fraction, the percentage in the middle.
    case filling(Double)
    /// No app can be played: black and white with a lock.
    case locked

    public static func make(game: PortedGame, portingGameID: UUID?, progress: PortingProgress?) -> PortingTileLook {
        if game.id == portingGameID, let progress {
            switch progress.phase {
            case .preparing:
                let title = progress.stageName.prefix(1).uppercased() + progress.stageName.dropFirst()
                return .preparing(step: progress.step, count: progress.count, title: title, detail: progress.stepName)
            case .shaders, .finishing: return .filling(progress.overall)
            case .done, .failed: break
            }
        }
        if !game.isPlayableLocally { return .locked }
        return .normal
    }
}

/// The pills under the game's title on Spotlight and Details.
public enum PortingPills: Equatable {
    /// Play (or Build), Options, Favorite.
    case normal
    /// One "Porting" pill.
    case porting
    /// Try again, Open log, Delete.
    case failed(PortingFailure)
    /// The normal pills over a working app, with a small "last porting failed" line.
    case normalAfterFailure(PortingFailure)
    /// Keep the entry and its options, with a disabled primary action and a short reason.
    case unavailable(GameUnavailableReason)

    public static func make(game: PortedGame, portingGameID: UUID?) -> PortingPills {
        if game.id == portingGameID { return .porting }
        if let reason = GameResourceState.unavailableReason(for: game) { return .unavailable(reason) }
        guard let failure = game.portingFailure else { return .normal }
        return game.isPlayableLocally ? .normalAfterFailure(failure) : .failed(failure)
    }

    public var count: Int { self == .porting ? 1 : 3 }

    public var unavailableReason: GameUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}
