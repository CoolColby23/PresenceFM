import Foundation
import UserNotifications

@MainActor
protocol NotificationDelivering {
    func requestAuthorization() async -> Bool
    func deliver(identifier: String, title: String, body: String, section: DashboardSection) async
}

@MainActor
final class SystemNotificationDelivery: NotificationDelivering {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func deliver(identifier: String, title: String, body: String, section: DashboardSection) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["section": section.rawValue]
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}

@MainActor
final class NotificationCoordinator {
    private let delivery: any NotificationDelivering
    private var delivered = Set<String>()

    init(delivery: any NotificationDelivering = SystemNotificationDelivery()) { self.delivery = delivery }

    func requestAuthorization() async -> Bool { await delivery.requestAuthorization() }

    func notifyOnce(key: String, title: String, body: String, section: DashboardSection) async {
        guard delivered.insert(key).inserted else { return }
        await delivery.deliver(identifier: "presencefm.\(key)", title: title, body: body, section: section)
    }

    func reset(_ key: String) { delivered.remove(key) }
}

extension Notification.Name {
    static let presenceFMOpenSection = Notification.Name("PresenceFMOpenSection")
    static let presenceFMPrivateModeIntent = Notification.Name("PresenceFMPrivateModeIntent")
}
