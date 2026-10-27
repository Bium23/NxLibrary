import SwiftUI

extension Notification.Name {
    static let nxLibraryPlayFocused = Notification.Name("NXLibraryPlayFocused")
    static let nxLibraryCheckUpstream = Notification.Name("NXLibraryCheckUpstream")
    static let nxLibraryOpenMenu = Notification.Name("NXLibraryOpenMenu")
}

@main
struct NXLibraryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
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
            CommandMenu("View") {
                Button("Menu") {
                    NotificationCenter.default.post(name: .nxLibraryOpenMenu, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
    }
}
