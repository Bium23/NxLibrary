import SwiftUI

extension Notification.Name {
    static let nxLibraryPlayFocused = Notification.Name("NXLibraryPlayFocused")
    static let nxLibraryCheckUpstream = Notification.Name("NXLibraryCheckUpstream")
}

@main
struct NXLibraryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
            CommandMenu("Engine") {
                Button("Check Upstream Changelog") {
                    NotificationCenter.default.post(name: .nxLibraryCheckUpstream, object: nil)
                }
                .keyboardShortcut("u", modifiers: [.command])
            }
        }
    }
}
