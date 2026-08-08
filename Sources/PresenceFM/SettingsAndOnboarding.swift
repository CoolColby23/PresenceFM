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
        VStack(spacing: BrandSpacing.xl) {
            header(preferences: preferences)
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
            }
            .frame(maxWidth: 600, minHeight: 330)
            .padding(28)
            .presenceCard(elevated: true)

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
        .padding(BrandSpacing.xxl)
        .frame(width: 760, height: 600)
        .presencePanelBackground()
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

    private func header(preferences: Preferences) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        BrandMark()
                            .frame(width: 32, height: 32)
                            .padding(8)
                            .background(.ultraThinMaterial, in: .circle)
                        Text("PresenceFM")
                            .font(BrandTypography.sectionTitle)
                    }
                    Text("Set up sharing, scrobbling, privacy, and startup behavior in a few quick steps.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if preferences.onboardingComplete {
                    Button("Close", systemImage: "xmark") {
                        model.onboardingPresented = false
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Close onboarding")
                    .accessibilityLabel("Close Onboarding")
                }
            }

            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(
                            index <= step
                                ? AnyShapeStyle(BrandColors.accentRibbon)
                                : AnyShapeStyle(BrandColors.steel.opacity(0.20))
                        )
                        .frame(height: 8)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step + 1) of \(steps.count): \(steps[step])")
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
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(BrandColors.accentRibbon.opacity(0.14))
                    .frame(width: 92, height: 92)
                if branded {
                    BrandMark().frame(width: 62, height: 62)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .foregroundStyle(BrandColors.electricBlue)
                }
            }
            Text(title).font(BrandTypography.heroTitle)
            Text(text)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
