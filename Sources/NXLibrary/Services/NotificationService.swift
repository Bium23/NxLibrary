import Foundation
import UserNotifications
import AppKit
import NXLibraryCore
import os

extension Notification.Name {
    /// A porting notification was clicked; userInfo carries "gameID" and "outcome" ("ready" or "failed").
    static let nxLibraryPortingNoticeOpened = Notification.Name("NXLibraryPortingNoticeOpened")
}

/// Sends the end-of-porting notification (`PortingNotice` decides when) and routes its click.
public final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationService()
    private static let log = Logger(subsystem: "local.nxlibrary", category: "notifications")

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error = error {
                Self.log.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func sendPortingEnded(gameID: UUID, gameName: String, success: Bool, reason: PortingFailureReason?,
                                 held: Bool = false) {
        let text = PortingNotice.text(game: gameName, success: success, reason: reason, held: held)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        content.userInfo = ["gameID": gameID.uuidString, "outcome": success ? "ready" : "failed"]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Self.log.error("Scheduling a notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .nxLibraryPortingNoticeOpened, object: nil, userInfo: info)
        }
        completionHandler()
    }
}
