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
        router.openSettings(.appearance)
        XCTAssertEqual(router.route, .settings(.appearance))
        router.back()
        XCTAssertEqual(router.route, .detail(id))
        router.back()
        XCTAssertEqual(router.route, .library)
        router.back()
        XCTAssertEqual(router.route, .library)
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
}

final class MenuSelectionModelTests: XCTestCase {
    func testMoveWraps() {
        var model = MenuSelectionModel()
        XCTAssertEqual(model.selected, .settings)
        model.move(by: 1)
        XCTAssertEqual(model.selected, .console)
        model.move(by: 1)
        XCTAssertEqual(model.selected, .quit)
        model.move(by: 1)
        XCTAssertEqual(model.selected, .library)
        model.move(by: -1)
        XCTAssertEqual(model.selected, .quit)
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
