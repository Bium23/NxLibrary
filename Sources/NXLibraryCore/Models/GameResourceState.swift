import Foundation

/// A missing app is different from missing inputs: a working app never needs its source files to Play.
public enum GameUnavailableReason: Equatable {
    case appMissing, sourcesMissing

    public var title: String {
        switch self {
        case .appMissing: return L10n.text("App not found")
        case .sourcesMissing: return L10n.text("Game files not found")
        }
    }

    public var detail: String {
        switch self {
        case .appMissing: return L10n.text("It may have been moved or removed.")
        case .sourcesMissing: return L10n.text("They may have been moved or removed.")
        }
    }
}

public enum GameResourceState {
    public static func sourcesAvailable(for game: PortedGame, fileManager: FileManager = .default) -> Bool {
        SourceSelection.hasGame(game.sources)
            && game.sources.allSatisfy { fileManager.fileExists(atPath: $0.url.path) }
    }

    public static func unavailableReason(for game: PortedGame) -> GameUnavailableReason? {
        if game.isPlayableLocally { return nil }
        if game.status == .appMissing { return .appMissing }
        if !game.sources.isEmpty, !sourcesAvailable(for: game) { return .sourcesMissing }
        return nil
    }

    /// Refresh disk observations while preserving unfinished builds and first-port failures.
    public static func reconciledStatus(for game: PortedGame, appExists: Bool,
                                        sourcesAvailable: Bool) -> GameStatus {
        guard game.status != .building else { return game.status }
        guard game.url.pathExtension.lowercased() == "app" else {
            // Older scans could label an unbuilt workspace as a missing app.
            guard game.status == .appMissing else { return game.status }
            switch game.portingFailure {
            case .failed: return .failed
            case .cancelled: return .cancelled
            case nil: return .notBuilt
            }
        }
        guard appExists else { return game.status == .notBuilt ? .notBuilt : .appMissing }
        guard game.status != .notBuilt else { return .notBuilt }
        if !sourcesAvailable { return .builtSourcesMissing }
        if [.builtSourcesMissing, .needsRebuild, .appMissing].contains(game.status) { return .built }
        return game.status
    }
}
