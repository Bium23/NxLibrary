import Foundation
import Combine

public enum AppRoute: Equatable {
    /// Spotlight, the home screen.
    case library
    /// The whole library as one grid (Selene's Collection).
    case collection
    case detail(UUID)
    case settings(SettingsSection)
    case addGame
    case console
}

public final class AppRouter: ObservableObject {
    @Published public private(set) var route: AppRoute = .library
    @Published public private(set) var isReturningFromBack = false
    @Published public var isMenuPresented = false
    @Published public var isSearchPresented = false
    /// True while the full-screen screenshot viewer is open; the shell ignores its global shortcuts.
    @Published public var isScreenshotViewerOpen = false
    @Published public var menuSelection = MenuSelectionModel()
    /// A Spotlight item key waiting to be lifted for moving (see `requestSpotlightMove`).
    @Published public var pendingSpotlightMove: String?
    /// A game id waiting for Spotlight to select it (Details' More like this).
    @Published public var pendingSpotlightSelect: UUID?

    private var history: [AppRoute] = []

    public init() {}

    /// The route the app opens on for the Start on setting.
    public static func initialRoute(for startOn: StartScreen, last: StartScreen) -> AppRoute {
        switch startOn {
        case .spotlight: return .library
        case .collection: return .collection
        case .last: return last == .collection ? .collection : .library
        }
    }

    /// Opens on `route` with nothing to go back to.
    public func setInitialRoute(_ route: AppRoute) {
        isReturningFromBack = false
        history.removeAll()
        self.route = route
    }

    /// Left and Right move along the row; while the Power pills are open they move the pills instead.
    public func moveMenu(by delta: Int) {
        if menuSelection.isPowerOpen {
            menuSelection.movePower(by: delta)
        } else {
            menuSelection.move(by: delta)
        }
    }

    public func openPowerMenu() { menuSelection.openPower() }

    /// B on the Power pills: closes them and leaves the menu open.
    public func closePowerMenu() { menuSelection.closePower() }

    public func navigate(to route: AppRoute) {
        guard route != self.route else { return }
        isReturningFromBack = false
        history.append(self.route)
        self.route = route
    }

    /// Asks Spotlight to select the item with this key and lift it for moving.
    /// Callers: a card's Y menu, and Game options' Move row.
    public func requestSpotlightMove(_ key: String) { pendingSpotlightMove = key }

    /// Asks Spotlight to select this game, switching to All games when the
    /// current filter hides it (the same path as Surprise me).
    public func requestSpotlightSelect(_ id: UUID) { pendingSpotlightSelect = id }

    public func showDetail(_ id: UUID) { navigate(to: .detail(id)) }
    public func openSettings(_ section: SettingsSection = .general) { navigate(to: .settings(section)) }
    public func openAddGame() { navigate(to: .addGame) }
    public func openConsole() { navigate(to: .console) }
    public func openCollection() { navigate(to: .collection) }

    public func showLibrary() {
        isReturningFromBack = false
        history.removeAll()
        route = .library
    }

    public func back() {
        guard let previous = history.popLast() else {
            isReturningFromBack = false
            return
        }
        isReturningFromBack = true
        route = previous
    }

    /// Closes the menu and, with it, the Power pills.
    public func closeMenu() {
        isMenuPresented = false
        menuSelection.closePower()
    }
}
