import NXLibraryCore
import SwiftUI

extension Notification.Name {
    static let nxLibraryPlayFocused = Notification.Name("NXLibraryPlayFocused")
    static let nxLibraryCheckAppUpdates = Notification.Name("NXLibraryCheckAppUpdates")
    static let nxLibraryOpenMenu = Notification.Name("NXLibraryOpenMenu")
    static let nxSettingsGamepadAction = Notification.Name("NXSettingsGamepadAction")
    static let nxLocalePickerGamepadAction = Notification.Name("NXLocalePickerGamepadAction")
    static let nxAddGameGamepadAction = Notification.Name("NXAddGameGamepadAction")
    static let nxConsoleGamepadAction = Notification.Name("NXConsoleGamepadAction")
    static let nxDetailGamepadAction = Notification.Name("NXDetailGamepadAction")
    static let nxSpotlightGamepadAction = Notification.Name("NXSpotlightGamepadAction")
    static let nxCollectionGamepadAction = Notification.Name("NXCollectionGamepadAction")
    static let nxGameOptionsGamepadAction = Notification.Name("NXGameOptionsGamepadAction")
    static let nxSetupCheckGamepadAction = Notification.Name("NXSetupCheckGamepadAction")
    static let nxThemePickerGamepadAction = Notification.Name("NXThemePickerGamepadAction")
    static let nxLibraryOpenSettings = Notification.Name("NXLibraryOpenSettings")
    static let nxLibraryRetryCatalogSave = Notification.Name("NXLibraryRetryCatalogSave")
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
    @ObservedObject private var localization = AppLocalization.shared
    var body: some Scene {
        Window("NX Library", id: "main") {
            DevelopmentStartupView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("Add Game…")) { NativeMenuCommands.shared.post(.nxLibraryOpenAddGame) }
                    .keyboardShortcut("n", modifiers: [.command])
                    .disabled(availability?.general != true)
            }
            CommandGroup(after: .newItem) {
                if availability?.catalogRecovery == true {
                    Button(L10n.text("Retry saving library")) { NativeMenuCommands.shared.post(.nxLibraryRetryCatalogSave) }
                        .keyboardShortcut("s", modifiers: [.command])
                }
            }
            CommandGroup(after: .appInfo) {
                Button(L10n.text("Check for Updates…")) { NativeMenuCommands.shared.post(.nxLibraryCheckAppUpdates) }
                    .disabled(availability?.general != true)
            }
            CommandGroup(replacing: .appSettings) {
                Button(L10n.text("Settings…")) {
                    NativeMenuCommands.shared.post(.nxLibraryOpenSettings)
                }
                .keyboardShortcut(",", modifiers: [.command])
                .disabled(availability?.general != true)
            }
            CommandMenu("Game") {
                Button(L10n.text("Add Game…")) {
                    NativeMenuCommands.shared.post(.nxLibraryOpenAddGame)
                }
                .disabled(availability?.general != true)
                Divider()
                Button(L10n.text("Play Selected Game")) {
                    NativeMenuCommands.shared.post(.nxLibraryPlayFocused)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(availability?.play != true)
                Divider()
                Button(L10n.text("Game Details")) {
                    NativeMenuCommands.shared.post(.nxLibraryOpenDetails)
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(availability?.details != true)
                Button(L10n.text("Game Options…")) {
                    NativeMenuCommands.shared.post(.nxLibraryOpenGameOptions)
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(availability?.options != true)
            }
            CommandGroup(after: .sidebar) {
                Button(L10n.text("Menu")) {
                    NativeMenuCommands.shared.post(.nxLibraryOpenMenu)
                }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(availability?.general != true)
            }
        }
    }
}
