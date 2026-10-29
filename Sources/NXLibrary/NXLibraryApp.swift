import SwiftUI

extension Notification.Name {
    static let nxLibraryPlayFocused = Notification.Name("NXLibraryPlayFocused")
    static let nxLibraryCheckUpstream = Notification.Name("NXLibraryCheckUpstream")
    static let nxLibraryOpenMenu = Notification.Name("NXLibraryOpenMenu")
    static let nxSettingsGamepadAction = Notification.Name("NXSettingsGamepadAction")
    static let nxAddGameGamepadAction = Notification.Name("NXAddGameGamepadAction")
    static let nxConsoleGamepadAction = Notification.Name("NXConsoleGamepadAction")
    static let nxDetailGamepadAction = Notification.Name("NXDetailGamepadAction")
    static let nxSpotlightGamepadAction = Notification.Name("NXSpotlightGamepadAction")
    static let nxGameOptionsGamepadAction = Notification.Name("NXGameOptionsGamepadAction")
    static let nxLibraryOpenSettings = Notification.Name("NXLibraryOpenSettings")
    static let nxLibraryOpenConsole = Notification.Name("NXLibraryOpenConsole")
    static let nxLibraryOpenLibrary = Notification.Name("NXLibraryOpenLibrary")
    static let nxLibraryOpenAddGame = Notification.Name("NXLibraryOpenAddGame")
    static let nxLibraryOpenDetails = Notification.Name("NXLibraryOpenDetails")
    static let nxLibraryOpenGameOptions = Notification.Name("NXLibraryOpenGameOptions")
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
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .nxLibraryOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandMenu("Game") {
                Button("Add Game…") {
                    NotificationCenter.default.post(name: .nxLibraryOpenAddGame, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
                Divider()
                Button("Play Selected Game") {
                    NotificationCenter.default.post(name: .nxLibraryPlayFocused, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                Divider()
                Button("Game Details") {
                    NotificationCenter.default.post(name: .nxLibraryOpenDetails, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command])
                Button("Game Options…") {
                    NotificationCenter.default.post(name: .nxLibraryOpenGameOptions, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
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
