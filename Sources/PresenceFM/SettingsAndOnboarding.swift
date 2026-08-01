import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var discordEnabled = false
    @State private var lastFMEnabled = false
    @State private var launchAtLogin = false
    @State private var selectedProviders = Set(PlaybackProviderID.allCases)
    @State private var hasLoadedPreferences = false

    private let steps = ["Welcome", "Music Players", "Discord", "Last.fm", "Privacy", "Startup", "Notifications", "Ready"]

    var body: some View {
        @Bindable var model = model
        @Bindable var preferences = model.preferences
        VStack(spacing: 24) {
            ZStack {
                HStack {
                    ForEach(steps.indices, id: \.self) { index in
                        Circle()
                            .fill(index <= step ? Color.accentColor : .secondary.opacity(0.25))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step + 1) of \(steps.count): \(steps[step])")

                if preferences.onboardingComplete {
                    HStack {
                        Spacer()
                        Button("Close", systemImage: "xmark") {
                            model.onboardingPresented = false
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .help("Close onboarding")
                        .accessibilityLabel("Close Onboarding")
                    }
                }
            }
            Group {
                switch step {
                case 0:
                    IntroStep(
                        title: "Welcome to PresenceFM", symbol: "waveform.circle.fill",
                        text:
                            "Your music, present. Share tracks from your music apps on Discord and preserve your listening history on Last.fm. Nothing is published until you enable it.",
                        branded: true
                    )
                case 1:
                    VStack(spacing: 14) {
                        IntroStep(
                            title: "Choose Your Players", symbol: "music.note",
                            text:
                                "Enable only the local players you use. Apple Music permission is requested only when Apple Music is enabled. YouTube Music requires YTMDesktop's Companion Server; TIDAL uses best-effort macOS Now Playing metadata."
                        )
                        ForEach(PlaybackProviderID.allCases) { provider in
                            Toggle(provider.displayName, isOn: providerBinding(provider)).frame(maxWidth: 360)
                        }
                    }
                case 2:
                    VStack(spacing: 16) {
                        IntroStep(
                            title: "Connect Discord", symbol: "bubble.left.and.bubble.right",
                            text: "PresenceFM includes its Discord application configuration. Keep Discord Desktop running, then enable Rich Presence."
                        )
                        Toggle("Enable Rich Presence", isOn: $discordEnabled)
                            .disabled(!ReleaseConfiguration.hasDiscordConfiguration)
                        if !ReleaseConfiguration.hasDiscordConfiguration {
                            Text("This development build does not include Discord configuration.")
                                .foregroundStyle(BrandColors.warning)
                        }
                    }
                case 3:
                    VStack(spacing: 16) {
                        IntroStep(
                            title: "Connect Last.fm", symbol: "dot.radiowaves.left.and.right",
                            text: "Enter the API key and shared secret from your Last.fm API account, then authorize PresenceFM."
                        )
                        SecureField("API Key", text: $model.credentialDraft.lastFMAPIKey)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Shared Secret", text: $model.credentialDraft.lastFMSecret)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Enable scrobbling", isOn: $lastFMEnabled)
                        HStack {
                            Button("Authorize") { Task { await model.beginLastFMAuthorization() } }
                                .disabled(
                                    model.credentialDraft.lastFMAPIKey.isEmpty
                                        || model.credentialDraft.lastFMSecret.isEmpty
                                )
                            Button("Complete Authorization") { Task { await model.completeLastFMAuthorization() } }
                                .disabled(model.lastFMStatus != .connecting)
                        }
                        if !model.lastFMUsername.isEmpty {
                            Label("Connected as \(model.lastFMUsername)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(BrandColors.success)
                        }
                    }.frame(maxWidth: 440)
                case 4:
                    IntroStep(
                        title: "Private by Default", symbol: "eye.slash",
                        text:
                            "Private Mode clears Discord presence and suppresses Last.fm updates. You can enable it temporarily from the menu bar at any time."
                    )
                case 5:
                    VStack(spacing: 16) {
                        IntroStep(
                            title: "Start Automatically", symbol: "power",
                            text: "PresenceFM can launch quietly when you log in."
                        )
                        Toggle("Launch at Login", isOn: $launchAtLogin)
                    }
                case 6:
                    VStack(spacing: 16) {
                        IntroStep(
                            title: "Actionable Notifications", symbol: "bell.badge",
                            text: "Notifications are only used for permission loss, expired authorization, or a persistently stuck queue."
                        )
                        Button("Allow Notifications") { Task { await model.requestNotifications() } }
                    }
                default:
                    IntroStep(
                        title: "PresenceFM Is Ready", symbol: "checkmark.circle.fill",
                        text:
                            "Play a song in one of your selected music apps. Optional integrations can be connected or skipped at any time, and every connection has a recovery path in the dashboard."
                    )
                }
            }.frame(maxWidth: 560, minHeight: 310)
            HStack {
                Button("Back") { step -= 1 }.disabled(step == 0)
                Spacer()
                if step < steps.count - 1 {
                    Button("Continue") { step += 1 }
                        .presenceButton(prominent: true)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Finish", action: finish)
                        .presenceButton(prominent: true)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(32)
        .frame(width: 700, height: 520)
        .interactiveDismissDisabled(!preferences.onboardingComplete)
        .onAppear(perform: loadPreferences)
        .onExitCommand {
            if preferences.onboardingComplete {
                model.onboardingPresented = false
            } else if step > 0 {
                step -= 1
            }
        }
    }

    private func providerBinding(_ provider: PlaybackProviderID) -> Binding<Bool> {
        Binding(
            get: { selectedProviders.contains(provider) },
            set: { enabled in
                if enabled { selectedProviders.insert(provider) } else { selectedProviders.remove(provider) }
            }
        )
    }

    private func finish() {
        model.preferences.enabledPlaybackProviders = selectedProviders
        model.setDiscordEnabled(discordEnabled)
        model.setLastFMEnabled(lastFMEnabled && !model.lastFMUsername.isEmpty)
        model.preferences.launchAtLogin = launchAtLogin
        model.setLaunchAtLogin(launchAtLogin)
        model.completeOnboarding()
    }

    private func loadPreferences() {
        guard !hasLoadedPreferences else { return }
        let preferences = model.preferences
        selectedProviders = preferences.enabledPlaybackProviders
        discordEnabled = preferences.discordEnabled
        lastFMEnabled = preferences.lastFMEnabled
        launchAtLogin = preferences.launchAtLogin
        hasLoadedPreferences = true
    }
}

struct IntroStep: View {
    let title: String
    let symbol: String
    let text: String
    var branded = false

    var body: some View {
        VStack(spacing: 18) {
            if branded { BrandMark().frame(width: 76, height: 76) } else { Image(systemName: symbol).font(.system(size: 64)).foregroundStyle(.tint) }
            Text(title).font(.largeTitle.bold())
            Text(text)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
