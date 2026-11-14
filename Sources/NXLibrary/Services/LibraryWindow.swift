import AppKit

/// NX Library's main window back in front after a game quits, for nxnative and Steam games alike.
@MainActor
enum LibraryWindow {
    /// macOS often makes NX Library the active app by itself as a game quits, but leaves the screen on the desktop
    /// while NX Library's full-screen window stays in its own Space: activating alone shows nothing. So the main
    /// window is also brought forward, which takes macOS to its Space. `ignoringOtherApps: true` covers the case
    /// where macOS put another app (Steam, for one) in front instead. Checked once more after the Space switch;
    /// never over an app `isGame` names.
    static func comeForward(unlessFront isGame: @escaping @MainActor (NSRunningApplication) -> Bool) {
        bringForward(mainWindow)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            let window = mainWindow
            guard !NSApp.isActive || window?.isOnActiveSpace == false else { return }
            if let front = NSWorkspace.shared.frontmostApplication, isGame(front) { return }
            bringForward(window)
        }
    }

    /// NX Library's main window: the visible one that can be main (not a panel or the menu bar's).
    private static var mainWindow: NSWindow? {
        NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }

    private static func bringForward(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
