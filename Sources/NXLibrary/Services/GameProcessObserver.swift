import AppKit
import NXLibraryCore

final class GameProcessObserver {
    private let store: PlaySessionStore
    private let center: NotificationCenter
    private var token: NSObjectProtocol?

    init(store: PlaySessionStore,
         center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.store = store
        self.center = center
    }

    func start() {
        token = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.store.end(bundleID: app.bundleIdentifier)
        }
    }

    func stop() {
        if let token { center.removeObserver(token) }
        token = nil
    }
}
