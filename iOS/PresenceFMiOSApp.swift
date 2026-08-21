import SwiftUI

@main struct PresenceFMiOSApp: App {
    @State private var model = CompanionAppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CompanionRootView(model: model)
                .task { await model.start() }
                .onOpenURL { url in Task { await model.handleLastFMCallback(url) } }
        }
        .backgroundTask(.appRefresh("fm.presence.companion.refresh")) {
            await model.reconcile(reportErrors: false); await model.scheduleBackgroundRefresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await model.refreshLastFMHistory()
                    if model.isReadyForCapture { await model.reconcile(reportErrors: false) }
                }
            }
        }
    }
}
