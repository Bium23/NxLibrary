import Foundation

/// Settings → Engine's Upstream row. Newer upstream commits are information: they reach players with NX Library
/// updates, once tested, never from here.
public enum UpstreamCopy {
    public static func subtitle(upToDate: Bool, newCommits: Int) -> String {
        if upToDate { return "This NX Library uses the newest nxnative." }
        return "nxnative has \(newCommits) newer commit\(newCommits == 1 ? "" : "s"). Engine updates reach you with NX Library updates, once tested."
    }
}
