import SwiftUI

extension Notification.Name {
    static let nxLibraryPlayFocused = Notification.Name("NXLibraryPlayFocused")
}

@main
struct NXLibraryApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 800)
        .commands {
            SidebarCommands()
            CommandMenu("Game") {
                Button("Play Selected Game") {
                    NotificationCenter.default.post(name: .nxLibraryPlayFocused, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }
}
