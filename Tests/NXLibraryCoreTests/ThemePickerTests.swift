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

    func testBackgroundsListTheThemeNoneAddThenYoursThenTheRest() {
        XCTAssertEqual(ThemeBackgrounds.list(themeID: "gruvbox", wallpapers: wallpapers),
                       [.theme, .none, .add, .wallpaper("custom/mine"), .wallpaper("gruvbox/2-b"), .wallpaper("kanagawa/1-a")],
                       "the theme's own wallpaper is Theme's own, not listed again")
        XCTAssertEqual(ThemeBackgrounds.list(themeID: "selene", wallpapers: wallpapers),
                       [.theme, .none, .add, .wallpaper("custom/mine"), .wallpaper("gruvbox/1-a"),
                        .wallpaper("gruvbox/2-b"), .wallpaper("kanagawa/1-a")])
    }

    func testTheSettingFindsItsTile() {
        let list = ThemeBackgrounds.list(themeID: "gruvbox", wallpapers: wallpapers)
        XCTAssertEqual(ThemeBackgrounds.index(of: nil, in: list), 0)
        XCTAssertEqual(ThemeBackgrounds.index(of: WallpaperCatalog.none, in: list), 1)
        XCTAssertEqual(ThemeBackgrounds.index(of: "kanagawa/1-a", in: list), 5)
        XCTAssertEqual(ThemeBackgrounds.index(of: "gruvbox/1-a", in: list), 0, "the theme's own is Theme's own")
        XCTAssertEqual(ThemeBackgrounds.index(of: "gone/x", in: list), 0)
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
}
