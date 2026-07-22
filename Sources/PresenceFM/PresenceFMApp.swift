import AppKit
import SwiftData
import SwiftUI
import UserNotifications

@main
struct PresenceFMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var updateManager = UpdateManager()

    init() {
        let launchInDemoMode = CommandLine.arguments.contains("--demo")
        do {
            let store = try PersistenceStore()
            _model = State(initialValue: AppModel(store: store, launchInDemoMode: launchInDemoMode))
        } catch {
            do {
                let store = try PersistenceStore(inMemory: true)
                let fallback = AppModel(store: store, launchInDemoMode: launchInDemoMode)
                fallback.usingTemporaryStore = true
                fallback.persistenceIssue = "PresenceFM could not open its local database. It is running with temporary data so the original store remains untouched. \(Redactor.redact(error.localizedDescription))"
                _model = State(initialValue: fallback)
            } catch {
                fatalError("PresenceFM could not create a recovery data store: \(Redactor.redact(error.localizedDescription))")
            }
        }
    }

    var body: some Scene {
        WindowGroup("PresenceFM", id: "dashboard") {
            DashboardView()
                .environment(model)
                .environment(updateManager)
                .tint(BrandColors.electricBlue)
        }
            .defaultSize(width: 980, height: 680)
            .modelContainer(model.store.container)

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            MenuBarBrandMark()
                .frame(width: 18, height: 18)
                .accessibilityLabel(model.isPrivate ? "PresenceFM, private" : "PresenceFM")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .environment(updateManager)
                .tint(BrandColors.electricBlue)
                .frame(minWidth: 620, minHeight: 520)
        }
            .modelContainer(model.store.container)

        .commands {
            PresenceFMCommands(model: model)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updateManager.checkForUpdates() }
            }
        }
    }
}

private struct PresenceFMCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel

    var body: some Commands {
        CommandMenu("Navigate") {
            ForEach(Array(DashboardSection.allCases.enumerated()), id: \.element.id) { index, section in
                Button(section.rawValue) {
                    model.selectedSection = section
                    NSApp.showDashboard(using: openWindow)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }

            Divider()

            if model.isPrivate {
                Button("End Private Mode") { model.endPrivateMode() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            } else {
                Button("Go Private Until Resumed") { model.setPrivate(until: nil) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}

extension NSApplication {
    func showDashboard(using openWindow: OpenWindowAction) {
        if let dashboard = windows.first(where: { $0.identifier?.rawValue.hasPrefix("dashboard-AppWindow") == true }) {
            dashboard.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "dashboard")
        }
        activate()
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
