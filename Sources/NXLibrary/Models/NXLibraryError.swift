import Foundation
import NXLibraryCore

public enum NXLibraryError: Error, LocalizedError {
    case baseRequired
    case missingSources
    case missingTitleId
    case missingKeys
    case engineMissing
    case environmentBlocked(String)
    case incompatibleToolchain(String)
    case buildAlreadyRunning
    case appMissing(String)
    case launchFailed(String)
    case noSelectedGame
    /// The imported keys cannot open the game (`KeyCheck`); the engine was not started.
    case keyCheck(PortingFailureReason, game: String)

    public var errorDescription: String? {
        switch self {
        case .baseRequired:
            return L10n.text("Select a base game. Updates and DLC alone cannot be built.")
        case .missingSources:
            return L10n.text("The source files are missing. Attach or locate the original base, update and DLC files first.")
        case .missingTitleId:
            return L10n.text("The game has no title ID. Choose a valid NSP, XCI, NSZ or XCZ source.")
        case .missingKeys:
            return L10n.text("prod.keys is missing. Import it in Settings.")
        case .engineMissing:
            return L10n.text("The nxnative checkout was not found. Choose it in Settings → Engine.")
        case .environmentBlocked(let detail):
            return L10n.format("The build environment is incomplete: %@", [String(describing: (detail))])
        case .incompatibleToolchain(let detail):
            return L10n.format("The toolchain is not certified: %@", [String(describing: (detail))])
        case .buildAlreadyRunning:
            return L10n.text("A build is already running.")
        case .appMissing(let path):
            return L10n.format("The app bundle is missing: %@", [String(describing: (path))])
        case .launchFailed(let name):
            return L10n.format("macOS could not launch %@.", [String(describing: (name))])
        case .noSelectedGame:
            return L10n.text("Select a game first.")
        case .keyCheck(let reason, let game):
            return "\(reason.what(game: game)) \(reason.next)"
        }
    }
}
