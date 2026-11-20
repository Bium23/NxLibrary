import Foundation
import Darwin

public enum BuildInstallError: Error, LocalizedError {
    case invalidApp(String)
    case replaceFailed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidApp(let p): return L10n.format("The built app is invalid: %@", [String(describing: p)])
        case .replaceFailed(let m): return L10n.format("Could not replace the app: %@", [String(describing: m)])
        }
    }
}

/// Filesystem boundary for failure and cross-volume tests.
package struct BuildInstallIO {
    package init() {}
    package var sameVolume: (URL, URL) throws -> Bool = { source, parent in
        var sourceInfo = stat(), parentInfo = stat()
        guard stat(source.path, &sourceInfo) == 0, stat(parent.path, &parentInfo) == 0 else {
            throw BuildInstallError.replaceFailed("Could not inspect the destination volume.")
        }
        return sourceInfo.st_dev == parentInfo.st_dev
    }
    package var publish: (URL, URL, Bool) throws -> Void = { source, destination, replacing in
        let flags = replacing ? RENAME_SWAP : RENAME_EXCL
        guard renamex_np(source.path, destination.path, UInt32(flags)) == 0 else {
            throw BuildInstallError.replaceFailed(String(cString: strerror(errno)))
        }
    }
    package var afterPublish: () throws -> Void = {}
}
