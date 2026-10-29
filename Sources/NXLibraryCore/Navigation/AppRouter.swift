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
    @Published public var menuSelection = MenuSelectionModel()

    private var history: [AppRoute] = []

    public init() {}

    public func moveMenu(by delta: Int) {
        menuSelection.move(by: delta)
    }

    public func navigate(to route: AppRoute) {
        guard route != self.route else { return }
        isReturningFromBack = false
        history.append(self.route)
        self.route = route
    }

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

    public func closeMenu() {
        isMenuPresented = false
    }
}
