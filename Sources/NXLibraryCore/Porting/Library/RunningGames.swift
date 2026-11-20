import Foundation

/// Matches the apps that are running against the library: a game is running when
/// its effective bundle id is one of the running applications' bundle ids.
public enum RunningGames {
    public static func matchingIDs(in games: [PortedGame], runningBundleIDs: Set<String>) -> Set<UUID> {
        guard !runningBundleIDs.isEmpty else { return [] }
        var ids = Set<UUID>()
        for game in games {
            guard let bundleID = game.effectiveBundleId, runningBundleIDs.contains(bundleID) else { continue }
            ids.insert(game.id)
        }
        return ids
    }
}
