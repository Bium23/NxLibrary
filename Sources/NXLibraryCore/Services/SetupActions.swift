import Foundation

public enum EngineAction: Equatable {
    case clone, checkout, none
}

/// The commands behind the Setup check's automatic cards, as argv lists so a
/// path with spaces stays one argument.
public enum SetupActions {
    public static let engineRemote = "https://github.com/seedds/nxnative"

    /// Only a missing engine or a clean checkout at another commit is changed;
    /// local changes are the player's and stay untouched.
    public static func engineAction(for facts: EngineFacts, pinned: String) -> EngineAction {
        switch facts {
        case .missing: return .clone
        case .checkout(let head, false) where head != pinned: return .checkout
        default: return .none
        }
    }

    /// Arguments for /usr/bin/git, run in order.
    public static func gitCommands(for action: EngineAction, folder: URL, pinned: String) -> [[String]] {
        let path = folder.path
        switch action {
        case .clone:
            return [["clone", "--progress", engineRemote, path], ["-C", path, "checkout", "--detach", pinned]]
        case .checkout:
            return [["-C", path, "fetch", "--progress", "origin"], ["-C", path, "checkout", "--detach", pinned]]
        case .none:
            return []
        }
    }
}
