import Foundation
import Darwin
import NXLibraryCore

/// Filesystem checks shared by saves; lstat never follows a substituted link.
internal enum SaveFiles {
    static func exists(_ url: URL) -> Bool {
        var s = stat(); return lstat(url.path, &s) == 0
    }
    static func safePath(_ url: URL) throws {
        // Foundation canonicalizes /private/var back to /var. Permit only Apple's
        // system aliases; links anywhere in the user-controlled tree remain refused.
        var path = url.path
        if path == "/var" || path.hasPrefix("/var/") || path == "/tmp" || path.hasPrefix("/tmp/") { path = "/private" + path }
        let standardized = URL(fileURLWithPath: path)
        guard !standardized.pathComponents.contains("..") else { throw SaveFailure.unsafePath }
        var current = URL(fileURLWithPath: "/")
        for component in standardized.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            var s = stat()
            if lstat(current.path, &s) == 0 {
                guard (s.st_mode & S_IFMT) == S_IFDIR || (s.st_mode & S_IFMT) == S_IFREG else { throw SaveFailure.unsafePath }
                if current.path != standardized.path && (s.st_mode & S_IFMT) != S_IFDIR { throw SaveFailure.unsafePath }
            } else if errno != ENOENT { throw SaveFailure.io("Could not inspect the save location.") }
        }
    }
}
