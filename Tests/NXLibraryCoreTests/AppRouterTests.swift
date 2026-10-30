import XCTest
@testable import NXLibraryCore

final class AppRouterTests: XCTestCase {
    func testInitialRoute() {
        let router = AppRouter()
        XCTAssertEqual(router.route, .library)
        XCTAssertFalse(router.isMenuPresented)
    }

    func testNavigationAndBack() {
        let router = AppRouter()
        let id = UUID()
        router.showDetail(id)
        XCTAssertEqual(router.route, .detail(id))
        router.openSettings(.look)
        XCTAssertEqual(router.route, .settings(.look))
        router.back()
        XCTAssertEqual(router.route, .detail(id))
        router.back()
        XCTAssertEqual(router.route, .library)
        router.back()
        XCTAssertEqual(router.route, .library)
    }

    func testRequestSpotlightSelectIsPending() {
        let router = AppRouter()
        let id = UUID()
        router.requestSpotlightSelect(id)
        XCTAssertEqual(router.pendingSpotlightSelect, id)
    }

    func testShowLibraryClearsHistory() {
        let router = AppRouter()
        router.openAddGame()
        router.showLibrary()
        XCTAssertEqual(router.route, .library)
        router.back()
        XCTAssertEqual(router.route, .library)
    }

    func testCollectionAndBackToSpotlight() {
        let router = AppRouter()
        router.openCollection()
        XCTAssertEqual(router.route, .collection)
        router.back()
        XCTAssertEqual(router.route, .library)
    }

    func testMenuOpenClose() {
        let router = AppRouter()
        router.isMenuPresented = true
        router.closeMenu()
        XCTAssertFalse(router.isMenuPresented)
    }

    func testMoveMenuMovesPillsWhileOpen() {
        let router = AppRouter()
        router.menuSelection.selected = .power
        router.openPowerMenu()
        router.movePowerMenu(by: 1)
        XCTAssertEqual(router.menuSelection.power, .hide)
        XCTAssertEqual(router.menuSelection.selected, .power)
        // Left and Right do nothing while the pills are open.
        router.moveMenu(by: -1)
        XCTAssertEqual(router.menuSelection.selected, .power)
        XCTAssertEqual(router.menuSelection.power, .hide)
        router.closePowerMenu()
        // Up and Down do nothing while the pills are closed.
        router.movePowerMenu(by: 1)
        XCTAssertEqual(router.menuSelection.power, .hide)
        router.moveMenu(by: -1)
        XCTAssertEqual(router.menuSelection.selected, .setupCheck)
    }

    func testCloseMenuClosesPowerPills() {
        let router = AppRouter()
        router.isMenuPresented = true
        router.openPowerMenu()
        router.closeMenu()
        XCTAssertFalse(router.isMenuPresented)
        XCTAssertFalse(router.menuSelection.isPowerOpen)
    }
}

final class MenuSelectionModelTests: XCTestCase {
    func testMenuOrder() {
        XCTAssertEqual(MenuAction.allCases,
                       [.addGame, .refreshLibrary, .settings, .wallpaper, .console, .setupCheck, .power])
        XCTAssertEqual(MenuAction.allCases.map(\.title),
                       ["Add Game", "Library refresh", "Settings", "Wallpaper", "Console", "Setup check", "Power"])
        XCTAssertEqual(PowerAction.allCases, [.quit, .hide, .relaunch])
        XCTAssertEqual(PowerAction.allCases.map(\.title), ["Quit", "Hide", "Restart app"])
    }

    func testMoveClampsAtBothEnds() {
        var model = MenuSelectionModel(selected: .addGame)
        model.move(by: -1)
        XCTAssertEqual(model.selected, .addGame)
        model.move(by: 10)
        XCTAssertEqual(model.selected, .power)
        model.move(by: 1)
        XCTAssertEqual(model.selected, .power)
    }

    func testPowerSubmenuOpensAndCloses() {
        var model = MenuSelectionModel(selected: .power)
        XCTAssertFalse(model.isPowerOpen)
        model.openPower()
        XCTAssertTrue(model.isPowerOpen)
        XCTAssertEqual(model.power, .quit)
        model.movePower(by: 1)
        XCTAssertEqual(model.power, .hide)
        model.movePower(by: 5)
        XCTAssertEqual(model.power, .relaunch)
        model.movePower(by: -9)
        XCTAssertEqual(model.power, .quit)
        model.closePower()
        XCTAssertFalse(model.isPowerOpen)
        XCTAssertEqual(model.selected, .power)
    }
}

final class AppRouterSpotlightMoveTests: XCTestCase {
    func testRequestSpotlightMoveSetsPendingKey() {
        let router = AppRouter()
        XCTAssertNil(router.pendingSpotlightMove)
        router.requestSpotlightMove("card:activity")
        XCTAssertEqual(router.pendingSpotlightMove, "card:activity")
    }

    func testInitialRouteHonorsStartOn() {
        XCTAssertEqual(AppRouter.initialRoute(for: .spotlight, last: .collection), .library)
        XCTAssertEqual(AppRouter.initialRoute(for: .collection, last: .spotlight), .collection)
        XCTAssertEqual(AppRouter.initialRoute(for: .last, last: .collection), .collection)
        XCTAssertEqual(AppRouter.initialRoute(for: .last, last: .spotlight), .library)
        // `last` is never a place; a stray one falls back to Spotlight.
        XCTAssertEqual(AppRouter.initialRoute(for: .last, last: .last), .library)
    }

    func testSetInitialRouteLeavesNoHistory() {
        let router = AppRouter()
        router.setInitialRoute(.collection)
        XCTAssertEqual(router.route, .collection)
        router.back()
        XCTAssertEqual(router.route, .collection)
    }
}
