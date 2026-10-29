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
