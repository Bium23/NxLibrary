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
            return "Select a base game. Updates and DLC alone cannot be built."
        case .missingSources:
            return "The source files are missing. Attach or locate the original base, update and DLC files first."
        case .missingTitleId:
            return "The game has no title ID. Choose a valid NSP, XCI, NSZ or XCZ source."
        case .missingKeys:
            return "prod.keys is missing. Import it in Settings."
        case .engineMissing:
            return "The nxnative checkout was not found. Choose it in Settings → Engine."
        case .environmentBlocked(let detail):
            return "The build environment is incomplete: \(detail)"
        case .incompatibleToolchain(let detail):
            return "The toolchain is not certified: \(detail)"
        case .buildAlreadyRunning:
            return "A build is already running."
        case .appMissing(let path):
            return "The app bundle is missing: \(path)"
        case .launchFailed(let name):
            return "macOS could not launch \(name)."
        case .noSelectedGame:
            return "Select a game first."
        case .keyCheck(let reason, let game):
            return "\(reason.what(game: game)) \(reason.next)"
        }
    }
}
