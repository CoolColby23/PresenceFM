import AppIntents
import Foundation

enum PrivateModeIntentAction: String, AppEnum {
    case start
    case end

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Private Mode Action")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .start: "Start Private Mode",
        .end: "End Private Mode",
    ]

    @MainActor
    func apply(to preferences: Preferences) {
        switch self {
        case .start:
            preferences.privateMode = true
            preferences.privateUntil = nil
        case .end:
            preferences.privateMode = false
            preferences.privateUntil = nil
        }
    }
}

struct SetPresenceFMPrivateModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set PresenceFM Private Mode"
    static let description = IntentDescription("Starts or ends PresenceFM Private Mode without sharing listening metadata.")

    @Parameter(title: "Action") var action: PrivateModeIntentAction

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$action) in PresenceFM")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            action.apply(to: Preferences.shared)
            NotificationCenter.default.post(
                name: .presenceFMPrivateModeIntent,
                object: nil,
                userInfo: ["action": action.rawValue]
            )
        }
        let message = action == .start ? "PresenceFM is private." : "PresenceFM sharing can resume."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct GetPresenceFMPrivacyStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get PresenceFM Privacy Status"
    static let description = IntentDescription("Reports whether PresenceFM Private Mode is active.")

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let isPrivate = await MainActor.run {
            let preferences = Preferences.shared
            return preferences.privateMode
                && (preferences.privateUntil == nil || preferences.privateUntil! > .now)
        }
        let message = isPrivate ? "PresenceFM Private Mode is on." : "PresenceFM Private Mode is off."
        return .result(value: isPrivate, dialog: IntentDialog(stringLiteral: message))
    }
}

struct OpenPresenceFMDashboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Open PresenceFM Dashboard"
    static let description = IntentDescription("Opens the PresenceFM Now Playing dashboard.")
    static var openAppWhenRun: Bool { true }

    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { [.foreground(.immediate)] }

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .presenceFMOpenSection,
            object: nil,
            userInfo: ["section": DashboardSection.nowPlaying.rawValue]
        )
        return .result()
    }
}

struct PresenceFMShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetPresenceFMPrivateModeIntent(),
            phrases: ["Set Private Mode in \(.applicationName)"],
            shortTitle: "Set Private Mode",
            systemImageName: "eye.slash"
        )
        AppShortcut(
            intent: GetPresenceFMPrivacyStatusIntent(),
            phrases: ["Check privacy in \(.applicationName)"],
            shortTitle: "Check Privacy",
            systemImageName: "checkmark.shield"
        )
        AppShortcut(
            intent: OpenPresenceFMDashboardIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open Dashboard",
            systemImageName: "music.note"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}
