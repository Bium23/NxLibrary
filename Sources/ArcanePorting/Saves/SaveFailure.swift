import Foundation
import NXLibraryCore

public enum SaveFailure: LocalizedError, Equatable {
    case invalidTitleID, unsafePath, customSavePath, unreadableConfiguration
    case cloudEnabled(String), running, busy, changed, emptyImport, invalidSnapshot, recoveryRequired, cloudPullPending
    case io(String)
    public var errorDescription: String? {
        switch self {
        case .invalidTitleID: return L10n.text("This game needs a valid title ID to manage saves.")
        case .unsafePath: return L10n.text("This save location contains a link or an unsafe path. Manage it in Finder.")
        case .customSavePath: return L10n.text("This game uses a custom save location. Manage it outside this panel.")
        case .unreadableConfiguration: return L10n.text("The game's save configuration could not be read.")
        case .cloudEnabled(let origin): return L10n.format("Cloud saves are enabled in %@. Turn them off there before importing or restoring.", [String(describing: origin)])
        case .running: return L10n.text("Close the game before managing its saves. Keep it closed until this operation finishes.")
        case .busy: return L10n.text("A save operation or app installation is in progress for this game.")
        case .changed: return L10n.text("The files changed since the preview. Choose the folder again.")
        case .emptyImport: return L10n.text("Choose a folder containing this game's actual save files.")
        case .invalidSnapshot: return L10n.text("This backup is incomplete, changed, or belongs to another game.")
        case .recoveryRequired: return L10n.text("Save recovery is required before Play. Your backup has been kept.")
        case .cloudPullPending: return L10n.text("A cloud save download did not finish. Play the game once so it can put this Mac's save back, then try again.")
        case .io(let message): return message
        }
    }
}
