import AppKit
import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func send(event: CheckEvent) {
        let check = event.check
        let content = UNMutableNotificationContent()
        content.title = "\(check.phase.notificationVerb): \(check.name)"
        content.subtitle = check.repositoryName
        if let provider = check.providerName {
            content.body = provider
        }
        content.sound = .default
        content.userInfo = ["url": check.url.absoluteString]

        let request = UNNotificationRequest(
            identifier: "\(check.id):\(check.phase.rawValue)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let value = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: value) else { return }
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }
}
