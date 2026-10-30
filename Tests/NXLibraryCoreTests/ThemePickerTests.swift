import XCTest
@testable import NXLibraryCore

final class ThemePickerTests: XCTestCase {
    private func wallpaper(_ id: String) -> Wallpaper {
        let parts = id.split(separator: "/")
        return Wallpaper(id: id, theme: String(parts[0]), url: URL(fileURLWithPath: "/w/\(id).jpg"))
    }

    private lazy var wallpapers = ["custom/mine", "gruvbox/1-a", "gruvbox/2-b", "kanagawa/1-a"].map(wallpaper)

    // MARK: - Grid

    /// Seven tiles in rows of three: 0 1 2 / 3 4 5 / 6.
    func testGridMovesWithinRowsAndBetweenThem() {
        XCTAssertEqual(GridNavigation.move(0, .right, count: 7, columns: 3), 1)
        XCTAssertNil(GridNavigation.move(2, .right, count: 7, columns: 3))
        XCTAssertNil(GridNavigation.move(3, .left, count: 7, columns: 3))
        XCTAssertEqual(GridNavigation.move(1, .down, count: 7, columns: 3), 4)
        XCTAssertEqual(GridNavigation.move(4, .down, count: 7, columns: 3), 6, "above the short last row's gap: its last tile")
        XCTAssertNil(GridNavigation.move(6, .down, count: 7, columns: 3))
        XCTAssertNil(GridNavigation.move(6, .right, count: 7, columns: 3))
        XCTAssertEqual(GridNavigation.move(6, .up, count: 7, columns: 3), 3)
        XCTAssertNil(GridNavigation.move(0, .up, count: 7, columns: 3))
    }

    func testPickerStepsUseTheirOwnColumns() {
        var state = ThemePickerState(themeIndex: 0, backgroundIndex: 0)
        XCTAssertTrue(state.move(.down, count: 23))
        XCTAssertEqual(state.themeIndex, ThemePickerState.themeColumns)
        state.step = .background
        XCTAssertTrue(state.move(.down, count: 9))
        XCTAssertEqual(state.backgroundIndex, ThemePickerState.backgroundColumns)
        XCTAssertEqual(state.themeIndex, ThemePickerState.themeColumns)
        XCTAssertFalse(state.move(.up, count: 9) && state.move(.up, count: 9))
    }

    // MARK: - Backgrounds

    /// First row: the online sources and + Add; then downloads, yours, the theme's own and none, the rest.
    func testBackgroundsOpenOnTheSourcesAndAdd() {
        XCTAssertEqual(ThemeBackgrounds.list(themeID: "gruvbox", wallpapers: wallpapers),
                       [.online(.wallhaven), .online(.danbooru), .add, .wallpaper("custom/mine"), .theme, .none,
                        .wallpaper("gruvbox/2-b"), .wallpaper("kanagawa/1-a")],
                       "the theme's own wallpaper is Theme's own, not listed again")
    }

    /// Selene has no wallpaper of its own: Theme's own would be the moonlight twice.
    func testAThemeWithoutAWallpaperOffersNoneOnly() {
        XCTAssertEqual(ThemeBackgrounds.list(themeID: "selene", wallpapers: wallpapers),
                       [.online(.wallhaven), .online(.danbooru), .add, .wallpaper("custom/mine"), .none,
                        .wallpaper("gruvbox/1-a"), .wallpaper("gruvbox/2-b"), .wallpaper("kanagawa/1-a")])
        let list = ThemeBackgrounds.list(themeID: "selene", wallpapers: wallpapers)
        XCTAssertEqual(ThemeBackgrounds.index(of: nil, in: list), 4, "following the theme is the moonlight")
    }

    func testDownloadsComeRightUnderTheFirstRow() {
        let all = (wallpapers + [wallpaper("online/wallhaven-abc"), wallpaper("online/danbooru-1")]).sorted { $0.id < $1.id }
        XCTAssertEqual(ThemeBackgrounds.list(themeID: "gruvbox", wallpapers: all),
                       [.online(.wallhaven), .online(.danbooru), .add,
                        .wallpaper("online/danbooru-1"), .wallpaper("online/wallhaven-abc"),
                        .wallpaper("custom/mine"), .theme, .none,
                        .wallpaper("gruvbox/2-b"), .wallpaper("kanagawa/1-a")])
        XCTAssertEqual(ThemeBackgrounds.group(.wallpaper("online/wallhaven-abc")), "DOWNLOADED")
        XCTAssertEqual(ThemeBackgrounds.group(.online(.wallhaven)), "ONLINE · WALLHAVEN")
        XCTAssertEqual(ThemeBackgrounds.group(.online(.danbooru)), "ONLINE · DANBOORU")
    }

    func testTheSettingFindsItsTile() {
        let list = ThemeBackgrounds.list(themeID: "gruvbox", wallpapers: wallpapers)
        XCTAssertEqual(ThemeBackgrounds.index(of: nil, in: list), 4)
        XCTAssertEqual(ThemeBackgrounds.index(of: WallpaperCatalog.none, in: list), 5)
        XCTAssertEqual(ThemeBackgrounds.index(of: "kanagawa/1-a", in: list), 7)
        XCTAssertEqual(ThemeBackgrounds.index(of: "gruvbox/1-a", in: list), 4, "the theme's own is Theme's own")
        XCTAssertEqual(ThemeBackgrounds.index(of: "gone/x", in: list), 4, "a missing file falls back to the theme")
    }

    func testGroupLabels() {
        XCTAssertEqual(ThemeBackgrounds.group(.theme), "THEME")
        XCTAssertEqual(ThemeBackgrounds.group(.none), "NO WALLPAPER")
        XCTAssertEqual(ThemeBackgrounds.group(.add), "YOUR OWN")
        XCTAssertEqual(ThemeBackgrounds.group(.wallpaper("custom/mine")), "YOUR OWN")
        XCTAssertEqual(ThemeBackgrounds.group(.wallpaper("rose-pine/1-x")), "ROSE PINE")
    }

    // MARK: - Your own

    func testCustomFileNamesAreTidyAndUnique() {
        XCTAssertEqual(WallpaperCatalog.customFileName(for: "My Photo!.JPG", existing: []), "my-photo.jpg")
        XCTAssertEqual(WallpaperCatalog.customFileName(for: "My Photo!.JPG", existing: ["my-photo"]), "my-photo-2.jpg")
        XCTAssertEqual(WallpaperCatalog.customFileName(for: "---.png", existing: []), "wallpaper.png")
        XCTAssertEqual(wallpaper("custom/my-photo").title, "Your own · My photo")
    }

    // MARK: - Wallpapers and Live

    private func video(_ id: String) -> Wallpaper {
        let parts = id.split(separator: "/")
        return Wallpaper(id: id, theme: String(parts[0]), url: URL(fileURLWithPath: "/w/\(id).mp4"))
    }

    private var withVideos: [Wallpaper] { wallpapers + [video("custom/rain"), video("live/steam-123")] }

    func testWallpapersTabListsStillsOnly() {
        XCTAssertEqual(ThemeBackgrounds.list(.wallpapers, themeID: "gruvbox", wallpapers: withVideos),
                       [.online(.wallhaven), .online(.danbooru), .add, .wallpaper("custom/mine"), .theme, .none,
                        .wallpaper("gruvbox/2-b"), .wallpaper("kanagawa/1-a")])
    }

    func testLiveOpensOnTheSourcesAndAddThenTheMoonlight() {
        XCTAssertEqual(ThemeBackgrounds.list(.live, themeID: "gruvbox", wallpapers: withVideos),
                       [.online(.motionbgs), .online(.steam), .add, .none,
                        .wallpaper("live/steam-123"), .wallpaper("custom/rain")])
        let list = ThemeBackgrounds.list(.live, themeID: "gruvbox", wallpapers: withVideos)
        XCTAssertEqual(ThemeBackgrounds.index(of: WallpaperCatalog.none, in: list), 3)
        XCTAssertEqual(ThemeBackgrounds.group(.online(.motionbgs), tab: .live), "ONLINE · MOTIONBGS")
        XCTAssertEqual(ThemeBackgrounds.group(.online(.steam), tab: .live), "ONLINE · STEAM")
    }

    func testLiveGroupLabels() {
        XCTAssertEqual(ThemeBackgrounds.group(.none, tab: .live), "THEME")
        XCTAssertEqual(ThemeBackgrounds.group(.add, tab: .live), "YOUR OWN")
        XCTAssertEqual(ThemeBackgrounds.group(.wallpaper("custom/rain"), tab: .live), "YOUR OWN")
        XCTAssertEqual(ThemeBackgrounds.group(.wallpaper("live/steam-123"), tab: .live), "DOWNLOADED")
        XCTAssertEqual(ThemeBackgrounds.group(.none, tab: .wallpapers), "NO WALLPAPER")
    }

    func testTheSettingOpensItsTab() {
        XCTAssertEqual(ThemeBackgrounds.tab(for: "custom/rain", wallpapers: withVideos), .live)
        XCTAssertEqual(ThemeBackgrounds.tab(for: "custom/mine", wallpapers: withVideos), .wallpapers)
        XCTAssertEqual(ThemeBackgrounds.tab(for: nil, wallpapers: withVideos), .wallpapers)
        XCTAssertEqual(ThemeBackgrounds.tab(for: WallpaperCatalog.none, wallpapers: withVideos), .wallpapers)
    }

    func testShouldersSwitchTabsAndTheFocusStartsOver() {
        var state = ThemePickerState(themeIndex: 0, backgroundIndex: 4)
        state.step = .background
        XCTAssertTrue(state.switchTab(to: .live))
        XCTAssertEqual(state.tab, .live)
        XCTAssertEqual(state.backgroundIndex, 0)
        XCTAssertFalse(state.switchTab(to: .live), "already there")
        state.step = .theme
        XCTAssertFalse(state.switchTab(to: .wallpapers), "the colors step has no tabs")
    }
}
