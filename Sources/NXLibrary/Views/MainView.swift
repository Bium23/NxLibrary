import SwiftUI
import NXLibraryCore

public struct MainView: View {
    private let settingsStore: AppSettingsStore

    public init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
    }

    public var body: some View { AppShellView(settingsStore: settingsStore) }
}
