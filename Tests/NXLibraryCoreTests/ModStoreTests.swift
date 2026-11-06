import XCTest
@testable import NXLibraryCore

final class ModStoreLayoutTests: XCTestCase {
    private func mod(_ id: Int, downloads: Int = 0, likes: Int = 0, added: TimeInterval = 0, updated: TimeInterval = 0,
                     category: String = "Skins", image: Bool = true) -> AvailableMod {
        AvailableMod(id: id, rank: id, name: "Mod \(id)", author: "A", avatarURL: nil,
                     images: image ? [URL(string: "https://images.gamebanana.com/img/ss/mods/\(id).jpg")!] : [],
                     thumbnailURL: image ? URL(string: "https://images.gamebanana.com/img/ss/mods/220-90_\(id).jpg")! : nil,
                     version: "", updated: Date(timeIntervalSince1970: updated),
                     pageURL: URL(string: "https://gamebanana.com/mods/\(id)")!, description: "", likes: likes,
                     downloads: downloads, files: [], category: category,
                     added: Date(timeIntervalSince1970: added))
    }

    func testGameBananaCategoriesGroupIntoOurs() {
        XCTAssertEqual(ModCategory.of("Skins"), .characters)
        XCTAssertEqual(ModCategory.of("Playable Characters"), .characters)
        XCTAssertEqual(ModCategory.of("Models"), .characters)
        XCTAssertEqual(ModCategory.of("Maps"), .worlds)
        XCTAssertEqual(ModCategory.of("Stages"), .worlds)
        XCTAssertEqual(ModCategory.of("Textures"), .graphics)
        XCTAssertEqual(ModCategory.of("Visual Overhaul"), .graphics)
        XCTAssertEqual(ModCategory.of("Effects"), .graphics)
        XCTAssertEqual(ModCategory.of("Music Packs"), .sound)
        XCTAssertEqual(ModCategory.of("Sounds"), .sound)
        XCTAssertEqual(ModCategory.of("GUIs"), .interface)
        XCTAssertEqual(ModCategory.of("UI"), .interface)
        XCTAssertEqual(ModCategory.of("Translations"), .interface)
        XCTAssertEqual(ModCategory.of("Gameplay"), .gameplay)
        XCTAssertEqual(ModCategory.of("Item"), .gameplay)
        XCTAssertEqual(ModCategory.of("Other/Misc"), .more)
        XCTAssertEqual(ModCategory.of("Game files"), .more)
        XCTAssertEqual(ModCategory.of(""), .more)
    }

    func testSortingIsLocalAndStable() {
        let a = mod(1, downloads: 10, likes: 5, added: 300, updated: 100)
        let b = mod(2, downloads: 30, likes: 1, added: 100, updated: 300)
        let c = mod(3, downloads: 20, likes: 9, added: 200, updated: 200)
        let entries = [a, b, c].map { ModCatalogEntry(mod: $0, titleID: "T", gameName: "G") }
        XCTAssertEqual(ModStoreLayout.sorted(entries, by: .popular).map(\.id), [2, 3, 1])
        XCTAssertEqual(ModStoreLayout.sorted(entries, by: .liked).map(\.id), [3, 1, 2])
        XCTAssertEqual(ModStoreLayout.sorted(entries, by: .newest).map(\.id), [1, 3, 2])
        XCTAssertEqual(ModStoreLayout.sorted(entries, by: .updated).map(\.id), [2, 3, 1])
    }

    func testSectionsRunDownSortFeaturedPopularCategoriesThenEachGame() {
        let zelda = ModCatalogGame(titleID: "Z", name: "Zelda", mods: [
            mod(1, downloads: 50, category: "Skins"), mod(2, downloads: 40, category: "Music Packs"),
            mod(3, downloads: 5, category: "Other/Misc", image: false)])
        let mario = ModCatalogGame(titleID: "M", name: "Mario", mods: [mod(4, downloads: 45, category: "Models")])
        let empty = ModCatalogGame(titleID: "E", name: "Empty", mods: [])
        let sections = ModStoreLayout.sections(games: [mario, zelda, empty], sort: .popular)
        XCTAssertEqual(sections.map(\.kind), [
            .sort, .featured, .popular,
            .category(.characters), .category(.sound), .category(.more),
            .game("M"), .game("Z")])
        XCTAssertEqual(sections[0].count, ModStoreSort.allCases.count)
        // Featured needs art, and takes each game's best first.
        XCTAssertEqual(sections[1].entries.map(\.id), [1, 4, 2])
        XCTAssertEqual(sections[2].entries.map(\.id), [1, 4, 2, 3])
        XCTAssertEqual(sections[3].entries.map(\.id), [1, 4])
        XCTAssertEqual(sections[6].title, "Mario")
        XCTAssertEqual(sections[7].entries.map(\.id), [1, 2, 3])
    }

    func testNoModsMeansOnlyTheSortBar() {
        XCTAssertEqual(ModStoreLayout.sections(games: [], sort: .popular).map(\.kind), [.sort])
    }

    func testRowsHoldAtMostTwelve() {
        let many = ModCatalogGame(titleID: "Z", name: "Zelda", mods: (1...20).map { mod($0, downloads: $0) })
        let sections = ModStoreLayout.sections(games: [many], sort: .popular)
        XCTAssertEqual(sections.first { $0.kind == .popular }?.entries.count, ModStoreLayout.rowLimit)
        XCTAssertEqual(sections.first { $0.kind == .featured }?.entries.count, ModStoreLayout.featuredCount)
        XCTAssertEqual(sections.first { $0.kind == .game("Z") }?.entries.count, ModStoreLayout.rowLimit)
    }

    func testSectionTopsAddUpFixedHeights() {
        let kinds: [ModStoreSectionKind] = [.sort, .featured, .popular, .game("Z")]
        XCTAssertEqual(ModStoreLayout.top(of: 0, in: kinds), 0)
        XCTAssertEqual(ModStoreLayout.top(of: 1, in: kinds), ModStoreLayout.height(.sort))
        XCTAssertEqual(ModStoreLayout.top(of: 3, in: kinds),
                       ModStoreLayout.height(.sort) + ModStoreLayout.height(.featured) + ModStoreLayout.height(.popular))
    }

    func testRowSlidesOnlyOnceTheFocusedTileReachesTheEdge() {
        let w = ModStoreLayout.tileWidth, g = ModStoreLayout.gap
        XCTAssertEqual(ModStoreLayout.rowScroll(index: nil), 0)
        XCTAssertEqual(ModStoreLayout.rowScroll(index: 4), 0)
        XCTAssertEqual(ModStoreLayout.rowScroll(index: 5), 5 * (w + g) + w + 28 - ModStoreLayout.clipWidth)
    }
}

final class ModStoreFocusTests: XCTestCase {
    private let counts: [(ModStoreSectionKind, Int)] = [(.sort, 4), (.featured, 3), (.popular, 8), (.game("Z"), 2)]
    private var sections: [ModStoreFocus.Section] { counts.map { ModStoreFocus.Section(kind: $0.0, count: $0.1) } }

    func testDownWalksTheSectionsAndUpLeavesAtTheTop() {
        var focus = ModStoreFocus()
        XCTAssertEqual(focus.kind, .sort)
        XCTAssertTrue(focus.down(in: sections))
        XCTAssertEqual(focus.kind, .featured)
        XCTAssertTrue(focus.down(in: sections))
        XCTAssertTrue(focus.down(in: sections))
        XCTAssertEqual(focus.kind, .game("Z"))
        XCTAssertFalse(focus.down(in: sections), "the last section holds")
        for _ in 0..<3 { XCTAssertTrue(focus.up(in: sections)) }
        XCTAssertFalse(focus.up(in: sections), "Up from the top leaves the store")
    }

    func testEachSectionRemembersItsTile() {
        var focus = ModStoreFocus()
        focus.down(in: sections)
        focus.down(in: sections)
        for _ in 0..<5 { XCTAssertTrue(focus.right(in: sections)) }
        XCTAssertEqual(focus.index, 5)
        focus.up(in: sections)
        XCTAssertEqual(focus.index, 0)
        focus.down(in: sections)
        XCTAssertEqual(focus.index, 5)
        for _ in 0..<5 { focus.right(in: sections) }
        XCTAssertEqual(focus.index, 7)
        XCTAssertFalse(focus.right(in: sections))
        XCTAssertTrue(focus.left(in: sections))
    }

    func testFeaturedWrapsAroundLikeACarousel() {
        var focus = ModStoreFocus()
        focus.down(in: sections)
        XCTAssertTrue(focus.left(in: sections))
        XCTAssertEqual(focus.index, 2)
        XCTAssertTrue(focus.right(in: sections))
        XCTAssertEqual(focus.index, 0)
    }

    func testFocusStaysOnItsSectionWhenRowsArriveAbove() {
        var focus = ModStoreFocus()
        focus.down(in: sections)
        focus.down(in: sections)
        focus.down(in: sections)
        XCTAssertEqual(focus.position(in: sections), 3)
        var more = sections
        more.insert(ModStoreFocus.Section(kind: .category(.characters), count: 4), at: 3)
        focus.settle(in: more)
        XCTAssertEqual(focus.kind, .game("Z"))
        XCTAssertEqual(focus.position(in: more), 4)
    }

    func testAVanishedSectionGivesWayToTheOneAbove() {
        var focus = ModStoreFocus()
        for _ in 0..<3 { focus.down(in: sections) }
        focus.settle(in: Array(sections.prefix(2)))
        XCTAssertEqual(focus.kind, .featured)
        focus.settle(in: [ModStoreFocus.Section(kind: .sort, count: 4), ModStoreFocus.Section(kind: .featured, count: 1)])
        XCTAssertEqual(focus.index, 0, "indexes are clamped to what a section holds")
    }
}

final class ModCatalogSnapshotTests: XCTestCase {
    func testSnapshotRoundTripsAndDropsUntrustedLinks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Snap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshots = ModCatalogSnapshots(folder: dir)
        let file = GameBananaFile(id: 9, name: "f.zip", size: 10, downloadURL: URL(string: "https://gamebanana.com/dl/9"),
                                  md5: "x", dateAdded: Date(timeIntervalSince1970: 5))
        let good = AvailableMod(id: 1, rank: 0, name: "One", author: "A", avatarURL: URL(string: "https://evil.example/a.png"),
                                images: [URL(string: "https://images.gamebanana.com/1.jpg")!, URL(string: "http://images.gamebanana.com/2.jpg")!],
                                thumbnailURL: URL(string: "https://images.gamebanana.com/t.jpg"), version: "1",
                                updated: Date(timeIntervalSince1970: 7), pageURL: URL(string: "https://gamebanana.com/mods/1")!,
                                description: "d", likes: 2, downloads: 3, files: [file], category: "Skins",
                                added: Date(timeIntervalSince1970: 4))
        try snapshots.save([good], gameName: "Zelda", titleID: "0100ABC", gameBananaID: 42, at: Date(timeIntervalSince1970: 100))
        let loaded = try XCTUnwrap(snapshots.load(titleID: "0100abc"))
        XCTAssertEqual(loaded.savedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(loaded.gameName, "Zelda")
        XCTAssertEqual(loaded.gameBananaID, 42)
        let mod = try XCTUnwrap(loaded.mods.first)
        XCTAssertEqual(mod.files, [file])
        XCTAssertEqual(mod.category, "Skins")
        XCTAssertEqual(mod.added, Date(timeIntervalSince1970: 4))
        XCTAssertNil(mod.avatarURL, "only GameBanana links survive the disk")
        XCTAssertEqual(mod.images, [URL(string: "https://images.gamebanana.com/1.jpg")!])
        XCTAssertNil(snapshots.load(titleID: "0100FFF"))
    }

    func testAModWithoutATrustedPageOrFileIsDropped() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Snap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshots = ModCatalogSnapshots(folder: dir)
        let badFile = GameBananaFile(id: 9, name: "f.zip", size: 10, downloadURL: URL(string: "https://evil.example/f.zip"), md5: "x")
        let mod = AvailableMod(id: 1, rank: 0, name: "One", author: "A", avatarURL: nil, images: [], thumbnailURL: nil,
                               version: "", updated: Date(), pageURL: URL(string: "https://gamebanana.com/mods/1")!,
                               description: "", likes: 0, downloads: 0, files: [badFile])
        try snapshots.save([mod], gameName: "Z", titleID: "T", gameBananaID: 1, at: Date())
        XCTAssertEqual(snapshots.load(titleID: "T")?.mods, [])
    }
}

final class ModCatalogSnapshotsAllTests: XCTestCase {
    func testLoadAllLeavesOutGamesWhosePageChanged() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Snap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshots = ModCatalogSnapshots(folder: dir.appendingPathComponent("store"))
        let matches = GameBananaMatchStore(file: dir.appendingPathComponent("matches.json"))
        let page = URL(string: "https://gamebanana.com/games/1")!
        let file = GameBananaFile(id: 1, name: "f.zip", size: 1, downloadURL: URL(string: "https://gamebanana.com/dl/1"), md5: "x")
        let mod = AvailableMod(id: 1, rank: 0, name: "M", author: "A", avatarURL: nil, images: [], thumbnailURL: nil,
                               version: "", updated: Date(), pageURL: URL(string: "https://gamebanana.com/mods/1")!,
                               description: "", likes: 0, downloads: 0, files: [file])
        try matches.set(.game(id: 1, name: "A", profileURL: page), titleID: "AAAA")
        try matches.set(.game(id: 3, name: "B", profileURL: page), titleID: "BBBB")
        try matches.set(.noPage, titleID: "CCCC")
        try snapshots.save([mod], gameName: "A", titleID: "AAAA", gameBananaID: 1)
        try snapshots.save([mod], gameName: "B", titleID: "BBBB", gameBananaID: 2)
        try snapshots.save([mod], gameName: "C", titleID: "CCCC", gameBananaID: 4)
        XCTAssertEqual(snapshots.loadAll(matches: matches).map(\.gameName), ["A"])
    }
}
