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

    /// Drawn over the screen it was opened from, which stays behind, blurred.
    public var isOverlay: Bool { self == .addGame || self == .console }
}

public final class AppRouter: ObservableObject {
    @Published public private(set) var route: AppRoute = .library
    @Published public private(set) var isReturningFromBack = false
    @Published public var isMenuPresented = false
    @Published public var isSearchPresented = false
    /// The cold-launch intro is on screen; screens ignore input until it ends.
    @Published public var isIntroShowing = false
    /// True while the full-screen screenshot viewer is open; the shell ignores its global shortcuts.
    @Published public var isScreenshotViewerOpen = false
    @Published public var menuSelection = MenuSelectionModel()
    /// The menu's Theme screen (colors, then background) is open in place of its row.
    @Published public var isThemePickerOpen = false
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

    /// Left and Right move along the row. They do nothing while the Power pills are open.
    public func moveMenu(by delta: Int) {
        guard !menuSelection.isPowerOpen else { return }
        menuSelection.move(by: delta)
    }

    /// Up and Down move the Power pills. They do nothing while the pills are closed.
    public func movePowerMenu(by delta: Int) {
        guard menuSelection.isPowerOpen else { return }
        menuSelection.movePower(by: delta)
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

    /// The screen under Add game or the console: the one they were opened from (Spotlight when unknown).
    public var underlyingRoute: AppRoute {
        history.last { !$0.isOverlay } ?? .library
    }

    public func showDetail(_ id: UUID) { navigate(to: .detail(id)) }
    public func openSettings(_ section: SettingsSection = .startUp) { navigate(to: .settings(section)) }
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

    /// Closes the menu and, with it, the Power pills and the Theme screen.
    public func closeMenu() {
        isMenuPresented = false
        isThemePickerOpen = false
        menuSelection.closePower()
    }
}
