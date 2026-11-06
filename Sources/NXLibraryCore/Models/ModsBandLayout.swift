import Foundation

/// What a status tile of the Mods band does.
public enum ModsBandAction: Hashable, Sendable {
    case retry
    case openPage(URL)
    /// "Is this the right game?": this GameBanana game id.
    case candidate(Int)
    case noneOfThese
    /// "No GameBanana page found": search GameBanana by name.
    case findGame
    case wrongGame
}

public enum ModsBandTile: Hashable, Sendable {
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

    /// The band is a grid that never slides sideways: six tiles to a row, as many rows as it needs, and Down walks
    /// the rows as in Build & Sources.
    public static let columns = 6

    public static func rows(count: Int) -> Int {
        count <= 0 ? 0 : (count - 1) / columns + 1
    }

    /// The tile under `index` in the next row; above a short last row's gap, its last tile; nil on the last row.
    public static func below(_ index: Int, count: Int) -> Int? {
        if index + columns < count { return index + columns }
        let lastRowStart = max(count - 1, 0) / columns * columns
        return index < lastRowStart ? count - 1 : nil
    }

    /// The tile above `index`; nil on the first row.
    public static func above(_ index: Int) -> Int? {
        index >= columns ? index - columns : nil
    }

    /// Left or Right inside the row; nil at the row's edge.
    public static func beside(_ index: Int, by delta: Int, count: Int) -> Int? {
        let column = index % columns
        if delta < 0 { return column > 0 ? index - 1 : nil }
        return column < columns - 1 && index + 1 < count ? index + 1 : nil
    }

    /// Down into the band: its first row, in the column it had.
    public static func entryFromAbove(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(index % columns, count - 1)
    }

    /// Up into the band: its last row, in the column it had.
    public static func entryFromBelow(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min((count - 1) / columns * columns + index % columns, count - 1)
    }
}
