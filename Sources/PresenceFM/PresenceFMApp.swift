import AppKit
import SwiftData
import SwiftUI

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
        Task { @MainActor in
            guard let app = NSApp.delegate as? AppDelegate else { return }
            _ = app
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
