import SwiftUI

@main struct PresenceFMiOSApp: App {
    @State private var model = CompanionAppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup { CompanionRootView(model: model).task { await model.start() } }
            .backgroundTask(.appRefresh("fm.presence.companion.refresh")) {
                await model.reconcile(); await model.scheduleBackgroundRefresh()
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.reconcile() } } }
    }
}
