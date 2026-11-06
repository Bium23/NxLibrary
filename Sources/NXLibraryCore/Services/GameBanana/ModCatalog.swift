import Foundation

/// The store's own categories, grouped from GameBanana's per-game root categories by name.
public enum ModCategory: String, CaseIterable, Codable, Sendable {
    case characters, worlds, graphics, sound, interface, gameplay, more

    public var title: String {
        switch self {
        case .characters: return "Characters & skins"
        case .worlds: return "Worlds & stages"
        case .graphics: return "Graphics & effects"
        case .sound: return "Music & sound"
        case .interface: return "Interface & text"
        case .gameplay: return "Gameplay"
        case .more: return "More mods"
        }
    }

    public var icon: MaterialIcon {
        switch self {
        case .characters: return .person
        case .worlds: return .landscape
        case .graphics: return .palette
        case .sound: return .music
        case .interface: return .translate
        case .gameplay: return .gamepad
        case .more: return .puzzle
        }
    }

    /// Words in GameBanana's category names, most specific group first.
    private static let words: [(ModCategory, [String])] = [
        (.sound, ["sound", "music", "audio", "voice", "song", "sfx"]),
        (.interface, ["gui", "ui", "hud", "menu", "font", "text", "translation", "language", "localization", "theme"]),
        (.worlds, ["map", "stage", "level", "world", "area", "track", "course", "arena"]),
        (.graphics, ["texture", "effect", "visual", "graphic", "shader", "lighting", "animation", "particle", "overhaul"]),
        (.characters, ["skin", "model", "character", "costume", "outfit", "fighter", "player", "npc", "armor", "weapon"]),
        (.gameplay, ["gameplay", "item", "event", "ai", "modpack", "mode", "balance", "difficulty", "spirit", "quest"])
    ]

    public static func of(_ rootCategory: String) -> ModCategory {
        let tokens = GameBananaMatch.normalized(rootCategory).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return .more }
        for (category, words) in words {
            // A word matches a token, or a plural of it ("Maps", "GUIs").
            if tokens.contains(where: { token in words.contains { token == $0 || token == $0 + "s" || token == $0 + "es" } }) {
                return category
            }
        }
        return .more
    }
}

/// How the store orders its mods. Sorting is local, over the mods already found: instant, no request.
public enum ModStoreSort: String, CaseIterable, Codable, Sendable {
    case popular, liked, newest, updated

    public var title: String {
        switch self {
        case .popular: return "Popular"
        case .liked: return "Most liked"
        case .newest: return "Newest"
        case .updated: return "Recently updated"
        }
    }

    public var icon: MaterialIcon {
        switch self {
        case .popular: return .trending
        case .liked: return .thumbUp
        case .newest: return .newReleases
        case .updated: return .update
        }
    }

    /// The title of the row of mods across your games.
    public var rowTitle: String {
        switch self {
        case .popular: return "Popular for your games"
        case .liked: return "Most liked for your games"
        case .newest: return "New for your games"
        case .updated: return "Recently updated for your games"
        }
    }
}

/// A mod in the store, with the game it is for.
public struct ModCatalogEntry: Equatable, Identifiable, Sendable {
    public let mod: AvailableMod
    public let titleID: String
    public let gameName: String
    public var id: Int { mod.id }
    public var category: ModCategory { ModCategory.of(mod.category) }

    public init(mod: AvailableMod, titleID: String, gameName: String) {
        self.mod = mod
        self.titleID = titleID
        self.gameName = gameName
    }
}

/// One of your games and its mods that work.
public struct ModCatalogGame: Equatable, Sendable {
    public let titleID: String
    public let name: String
    public let mods: [AvailableMod]

    public init(titleID: String, name: String, mods: [AvailableMod]) {
        self.titleID = titleID
        self.name = name
        self.mods = mods
    }

    public var entries: [ModCatalogEntry] { mods.map { ModCatalogEntry(mod: $0, titleID: titleID, gameName: name) } }
}

public enum ModStoreSectionKind: Hashable, Sendable {
    case sort, featured, popular
    case category(ModCategory)
    /// One of your games, by title ID.
    case game(String)
}

public struct ModStoreSection: Equatable, Identifiable, Sendable {
    public let kind: ModStoreSectionKind
    public let title: String
    public let entries: [ModCatalogEntry]
    public var id: ModStoreSectionKind { kind }
    /// What Left/Right moves through: the sort choices, or the tiles.
    public var count: Int { kind == .sort ? ModStoreSort.allCases.count : entries.count }
}

/// The store page, top to bottom: the sort bar, Featured, the mods across your games, a row per category, a row per
/// game (in the order given, last played first). Every section has a fixed height, so the page scrolls without
/// measuring anything.
public enum ModStoreLayout {
    public static let rowLimit = 12
    public static let featuredCount = 5

    // Canvas units.
    public static let tileWidth: CGFloat = 336
    public static let tileHeight: CGFloat = 189
    public static let gap: CGFloat = 20
    /// The screenshot strip's clip, so every row ends at the same edge.
    public static let clipWidth: CGFloat = 1788

    public static func height(_ kind: ModStoreSectionKind) -> CGFloat {
        switch kind {
        case .sort: return 110
        case .featured: return 470
        case .popular, .category, .game: return tileHeight + 136
        }
    }

    /// The top of section `index`, from the page's top.
    public static func top(of index: Int, in kinds: [ModStoreSectionKind]) -> CGFloat {
        kinds.prefix(max(index, 0)).reduce(0) { $0 + height($1) }
    }

    /// How far a row slides so tile `index` and its ring stay inside the clip: nothing until the tile reaches the
    /// right edge, as in the screenshot strip.
    public static func rowScroll(index: Int?) -> CGFloat {
        guard let index, index > 0 else { return 0 }
        let right = CGFloat(index) * (tileWidth + gap) + tileWidth + 28
        return max(0, right - clipWidth)
    }

    public static func sorted(_ entries: [ModCatalogEntry], by sort: ModStoreSort) -> [ModCatalogEntry] {
        func key(_ e: ModCatalogEntry) -> (Double, Double) {
            let m = e.mod
            switch sort {
            case .popular: return (Double(m.downloads), Double(m.likes))
            case .liked: return (Double(m.likes), Double(m.downloads))
            case .newest: return ((m.added ?? m.updated).timeIntervalSince1970, Double(m.downloads))
            case .updated: return (m.updated.timeIntervalSince1970, Double(m.downloads))
            }
        }
        return entries.sorted { a, b in
            let ka = key(a), kb = key(b)
            if ka != kb { return ka > kb }
            return a.id < b.id
        }
    }

    public static func sections(games: [ModCatalogGame], sort: ModStoreSort) -> [ModStoreSection] {
        var sections = [ModStoreSection(kind: .sort, title: "Sort", entries: [])]
        var seen = Set<Int>()
        // A mod listed under two games (shared by both) appears once, under the first.
        let all = sorted(games.flatMap(\.entries).filter { seen.insert($0.id).inserted }, by: sort)
        guard !all.isEmpty else { return sections }

        sections.append(ModStoreSection(kind: .featured, title: "Featured", entries: featured(all)))
        sections.append(ModStoreSection(kind: .popular, title: sort.rowTitle, entries: Array(all.prefix(rowLimit))))
        for category in ModCategory.allCases {
            let entries = all.filter { $0.category == category }
            if !entries.isEmpty {
                sections.append(ModStoreSection(kind: .category(category), title: category.title,
                                                entries: Array(entries.prefix(rowLimit))))
            }
        }
        for game in games where !game.mods.isEmpty {
            sections.append(ModStoreSection(kind: .game(game.titleID), title: game.name,
                                            entries: Array(sorted(game.entries, by: sort).prefix(rowLimit))))
        }
        return sections.filter { $0.kind == .sort || !$0.entries.isEmpty }
    }

    /// Mods with art, each game's best first so the banner is varied, then the next best.
    private static func featured(_ sorted: [ModCatalogEntry]) -> [ModCatalogEntry] {
        let withArt = sorted.filter { !$0.mod.images.isEmpty || $0.mod.thumbnailURL != nil }
        var games = Set<String>()
        let firsts = withArt.filter { games.insert($0.titleID).inserted }
        let firstIDs = Set(firsts.map(\.id))
        let rest = withArt.filter { !firstIDs.contains($0.id) }
        return Array((firsts + rest).prefix(featuredCount))
    }
}
