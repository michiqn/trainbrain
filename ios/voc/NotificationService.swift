//
//  NotificationService.swift
//  voc
//

import os
import UserNotifications

/// Posts local notifications.
///
/// It is also the notification center's delegate. Without a delegate, iOS hides
/// notifications while the app is in the foreground, which is exactly when this app posts them.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "voc", category: "Notifications")

    private override init() {
        super.init()
    }

    /// Becomes the notification center's delegate and asks for permission. Call once at launch.
    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [logger] _, error in
            if let error {
                logger.error("Notification authorization failed: \(error.localizedDescription)")
            }
        }
    }

    func show(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
