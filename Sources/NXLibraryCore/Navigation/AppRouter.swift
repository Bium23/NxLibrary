import Foundation
import Combine

public enum AppRoute: Equatable {
    case library
    case detail(UUID)
    case settings(SettingsSection)
    case addGame
    case console
}

public final class AppRouter: ObservableObject {
    @Published public private(set) var route: AppRoute = .library
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
        history.append(self.route)
        self.route = route
    }

    public func showDetail(_ id: UUID) { navigate(to: .detail(id)) }
    public func openSettings(_ section: SettingsSection = .general) { navigate(to: .settings(section)) }
    public func openAddGame() { navigate(to: .addGame) }
    public func openConsole() { navigate(to: .console) }

    public func showLibrary() {
        history.removeAll()
        route = .library
    }

    public func back() {
        guard let previous = history.popLast() else { return }
        route = previous
    }

    public func closeMenu() {
        isMenuPresented = false
    }
}
