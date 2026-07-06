import Foundation
import UserNotifications

enum NotificationManager {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(kind: WindowKind, threshold: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Claude \(kind.title) usage"
        content.body = "You've used \(Int(threshold * 100))% of your \(kind.title.lowercased()) limit."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
