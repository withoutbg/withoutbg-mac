import AppKit
import UserNotifications

/// Posts a local notification when a background-removal batch finishes while the
/// app is in the background — so users can switch away and get pinged when their
/// cutouts are ready.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyBatchFinished(done: Int, failed: Int) {
        // Don't interrupt active use — only notify when we're not frontmost.
        guard !NSApp.isActive else { return }

        let content = UNMutableNotificationContent()
        content.title = "Backgrounds removed"
        let images = "\(done) image\(done == 1 ? "" : "s")"
        content.body = failed > 0 ? "\(images) ready · \(failed) failed" : "\(images) ready"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
