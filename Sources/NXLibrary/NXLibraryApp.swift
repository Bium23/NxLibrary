import SwiftUI

extension Notification.Name {
    static let nxLibraryPlayFocused = Notification.Name("NXLibraryPlayFocused")
    static let nxLibraryCheckAppUpdates = Notification.Name("NXLibraryCheckAppUpdates")
    static let nxLibraryOpenMenu = Notification.Name("NXLibraryOpenMenu")
    static let nxSettingsGamepadAction = Notification.Name("NXSettingsGamepadAction")
    static let nxAddGameGamepadAction = Notification.Name("NXAddGameGamepadAction")
    static let nxConsoleGamepadAction = Notification.Name("NXConsoleGamepadAction")
    static let nxDetailGamepadAction = Notification.Name("NXDetailGamepadAction")
    static let nxSpotlightGamepadAction = Notification.Name("NXSpotlightGamepadAction")
    static let nxCollectionGamepadAction = Notification.Name("NXCollectionGamepadAction")
    static let nxGameOptionsGamepadAction = Notification.Name("NXGameOptionsGamepadAction")
    static let nxSetupCheckGamepadAction = Notification.Name("NXSetupCheckGamepadAction")
    static let nxThemePickerGamepadAction = Notification.Name("NXThemePickerGamepadAction")
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
    @FocusedValue(\.nxMenuAvailability) private var availability

    var body: some Scene {
        Window("NX Library", id: "main") {
            MainView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("Add Game…") { NativeMenuCommands.shared.post(.nxLibraryOpenAddGame) }
                    .keyboardShortcut("n", modifiers: [.command])
                    .disabled(availability?.general != true)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { NativeMenuCommands.shared.post(.nxLibraryCheckAppUpdates) }
                    .disabled(availability?.general != true)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NativeMenuCommands.shared.post(.nxLibraryOpenSettings)
                }
                .keyboardShortcut(",", modifiers: [.command])
                .disabled(availability?.general != true)
            }
            CommandMenu("Game") {
                Button("Add Game…") {
                    NativeMenuCommands.shared.post(.nxLibraryOpenAddGame)
                }
                .disabled(availability?.general != true)
                Divider()
                Button("Play Selected Game") {
                    NativeMenuCommands.shared.post(.nxLibraryPlayFocused)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(availability?.play != true)
                Divider()
                Button("Game Details") {
                    NativeMenuCommands.shared.post(.nxLibraryOpenDetails)
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(availability?.details != true)
                Button("Game Options…") {
                    NativeMenuCommands.shared.post(.nxLibraryOpenGameOptions)
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(availability?.options != true)
            }
            CommandGroup(after: .sidebar) {
                Button("Menu") {
                    NativeMenuCommands.shared.post(.nxLibraryOpenMenu)
                }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(availability?.general != true)
            }
        }
    }
}
