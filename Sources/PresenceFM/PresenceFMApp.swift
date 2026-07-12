import AppKit
import SwiftData
import SwiftUI
import UserNotifications

@main
struct PresenceFMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        let store = try! PersistenceStore()
        _model = State(initialValue: AppModel(store: store))
    }

    var body: some Scene {
        WindowGroup("PresenceFM", id: "dashboard") {
            DashboardView().environment(model).tint(BrandColors.electricBlue)
        }
            .defaultSize(width: 980, height: 680)
            .modelContainer(model.store.container)

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            BrandMark(isPrivate: model.isPrivate, monochrome: true)
                .frame(width: 18, height: 18)
                .accessibilityLabel(model.isPrivate ? "PresenceFM, private" : "PresenceFM")
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView().environment(model).tint(BrandColors.electricBlue).frame(minWidth: 620, minHeight: 520) }
            .modelContainer(model.store.container)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        UNUserNotificationCenter.current().delegate = self
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let section = response.notification.request.content.userInfo["section"] as? String
        await MainActor.run {
            NotificationCenter.default.post(
                name: .presenceFMOpenSection,
                object: nil,
                userInfo: section.map { ["section": $0] }
            )
        }
    }
}
