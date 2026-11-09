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
            if let last = lastFinishingSeconds { return "About \(duration(eta + last)) left" }
            return "Shaders: about \(duration(eta))"
        case .finishing:
            if let eta = progress.finishingETA { return "Pipelines: about \(duration(eta))" }
            guard let last = lastFinishingSeconds else { return "Finishing up" }
            return "About \(duration(max(0, last - progress.finishingElapsed))) left"
        case .preparing, .done, .failed:
            return nil
        }
    }

    /// Stage time in the Porting list: seconds under a minute, m:ss under an hour, h:mm:ss from an hour on.
    public static func elapsed(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) s" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func minutes(_ seconds: Double) -> Int {
        max(1, Int((seconds / 60).rounded()))
    }

    static func duration(_ seconds: Double) -> String {
        let total = minutes(seconds)
        let hours = total / 60
        let mins = total % 60
        if hours == 0 { return L10n.format("%@ min", [String(describing: (mins))]) }
        if mins == 0 { return L10n.format("%@ hr", [String(describing: (hours))]) }
        return L10n.format("%@ hr %@ min", [String(describing: (hours)), String(describing: (mins))])
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
