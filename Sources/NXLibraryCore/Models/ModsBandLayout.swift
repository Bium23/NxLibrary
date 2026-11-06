import Foundation

/// What a status tile of the Mods band does.
public enum ModsBandAction: Equatable, Sendable {
    case retry
    case openPage(URL)
    /// "Is this the right game?": this GameBanana game id.
    case candidate(Int)
    case noneOfThese
    /// "No GameBanana page found": search GameBanana by name.
    case findGame
    case wrongGame
}

public enum ModsBandTile: Equatable, Sendable {
    /// An installed mod, by its index in the list.
    case installed(Int)
    case manage
    /// A GameBanana mod that works, by mod id.
    case available(Int)
    case status(ModsBandAction)
}

/// The Mods band's tiles, left to right: installed mods (at most 5), Manage mods, the GameBanana mods that work,
/// then the status tiles (Retry, the match question, Wrong game?…).
public enum ModsBandLayout {
    public static let maxInstalled = 5

    public static func tiles(installed: Int, available: [Int], status: [ModsBandAction]) -> [ModsBandTile] {
        (0..<min(max(installed, 0), maxInstalled)).map(ModsBandTile.installed) + [.manage]
            + available.map(ModsBandTile.available) + status.map(ModsBandTile.status)
    }

    public static func tileCount(installed: Int, available: Int, statusTiles: Int) -> Int {
        min(max(installed, 0), maxInstalled) + 1 + max(available, 0) + max(statusTiles, 0)
    }

    /// The first tile shown when the row slides so the focused tile stays on screen.
    public static func scrollIndex(focused: Int?, count: Int, visible: Int) -> Int {
        guard let focused, visible > 0 else { return 0 }
        return min(max(0, focused - visible + 1), max(0, count - visible))
    }
}
