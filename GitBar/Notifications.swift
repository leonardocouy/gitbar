import Foundation
import UserNotifications

struct GitBarNotifier {
    func notify(title: String = "GitBar", body: String) {
        guard !body.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        center.add(request)
    }
}

