import AppKit
import Foundation
import OSLog
import UserNotifications

enum NotificationPermission: Equatable {
    case unknown
    case enabled
    case disabled
}

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CheckCheck",
        category: "Notifications"
    )

    override init() {
        super.init()
        center.delegate = self
    }

    func prepareAuthorization() async -> NotificationPermission {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .enabled
        case .denied:
            return .disabled
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                return granted ? .enabled : .disabled
            } catch {
                logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                return .disabled
            }
        @unknown default:
            return .disabled
        }
    }

    func send(event: CheckEvent) async -> NotificationPermission {
        let permission = await prepareAuthorization()
        guard permission == .enabled else { return permission }

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
        do {
            try await center.add(request)
        } catch {
            logger.error("Notification delivery failed: \(error.localizedDescription, privacy: .public)")
        }
        return permission
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
