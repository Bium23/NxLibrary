import Foundation
import NXLibraryCore

/// Settings → Setup and engine's Upstream row. Newer upstream commits are information: they reach players with Arcane
/// updates, once tested. The Newest engine row is the only way to use them earlier, by the player's own choice.
public enum UpstreamCopy {
    public static func subtitle(upToDate: Bool, newCommits: Int) -> String {
        if upToDate { return L10n.text("This version of Arcane uses the newest nxnative.") }
        return L10n.count("nxnative has %lld newer commits. Engine updates reach you with Arcane updates, once tested.", newCommits, arguments: [])
    }
}
