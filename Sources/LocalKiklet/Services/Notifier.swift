import Foundation
import UserNotifications

final class Notifier: @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()
    private let logger: AppLogger

    init(logger: AppLogger = .shared) {
        self.logger = logger
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                self.logger.warn("Notification permission failed: \(error.localizedDescription)")
            }
        }
    }

    func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { [logger] error in
            if let error {
                logger.warn("Notification dispatch failed: \(error.localizedDescription)")
            }
        }
    }
}
