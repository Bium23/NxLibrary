import SwiftUI
import NXLibraryCore

public struct MainView: View {
    private let state: AppShellState

    @MainActor init(state: AppShellState) {
        self.state = state
    }

    public var body: some View { AppShellView(state: state) }
}
