import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showAdvancedCredentials = false

    var body: some View {
        @Bindable var model = model
        @Bindable var preferences = model.preferences
        Form {
            Section("General") {
                Toggle("Launch PresenceFM at login", isOn: $preferences.launchAtLogin).onChange(of: preferences.launchAtLogin) { _, value in model.setLaunchAtLogin(value) }
                Button("Run Onboarding Again") { model.onboardingPresented = true }
            }
            Section("Listening History") {
                Picker("Keep history", selection: $preferences.historyRetentionDays) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                    Text("Forever").tag(0)
                }
                .onChange(of: preferences.historyRetentionDays) { _, _ in model.applyHistoryRetention() }
                Text("History stays on this Mac and is never uploaded by PresenceFM.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Discord") {
                Toggle("Enable Discord Rich Presence", isOn: $preferences.discordEnabled).onChange(of: preferences.discordEnabled) { _, value in model.setDiscordEnabled(value) }
                Toggle("Show album", isOn: $preferences.showAlbum).onChange(of: preferences.showAlbum) { _, _ in model.refreshPresenceOptions() }
                Toggle("Show timer", isOn: $preferences.showTimer).onChange(of: preferences.showTimer) { _, _ in model.refreshPresenceOptions() }
                Toggle("Show Apple Music link", isOn: $preferences.showLink).onChange(of: preferences.showLink) { _, _ in model.refreshPresenceOptions() }
                Picker("First line", selection: $preferences.discordLineOne) {
                    ForEach(DiscordLineFormat.allCases) { Text($0.rawValue).tag($0) }
                }.onChange(of: preferences.discordLineOne) { _, _ in model.refreshPresenceOptions() }
                Picker("Second line", selection: $preferences.discordLineTwo) {
                    ForEach(DiscordLineFormat.allCases) { Text($0.rawValue).tag($0) }
                }.onChange(of: preferences.discordLineTwo) { _, _ in model.refreshPresenceOptions() }
                TextField("Button label", text: $preferences.discordButtonLabel)
                    .onSubmit { model.refreshPresenceOptions() }
                Text("Discord limits button labels to 32 characters. Changes apply to the next presence update.")
                    .font(.caption).foregroundStyle(.secondary)
                if preferences.discordEnabled { Button("Reconnect to Discord") { model.refreshDiscord() } }
            }
            Section("Last.fm") {
                SecureField("API Key", text: $model.credentialDraft.lastFMAPIKey)
                SecureField("Shared Secret", text: $model.credentialDraft.lastFMSecret)
                Toggle("Enable scrobbling", isOn: $preferences.lastFMEnabled).onChange(of: preferences.lastFMEnabled) { _, value in model.setLastFMEnabled(value) }
                Toggle("Send now playing", isOn: $preferences.sendNowPlaying)
                if !model.lastFMUsername.isEmpty {
                    LabeledContent("Connected account", value: model.lastFMUsername)
                    Button("Disconnect Last.fm", role: .destructive) {
                        preferences.lastFMEnabled = false
                        Task { await model.disconnectLastFM() }
                    }
                }
                HStack {
                    Button("Authorize in Browser") { Task { await model.beginLastFMAuthorization() } }
                        .disabled(model.credentialDraft.lastFMAPIKey.isEmpty || model.credentialDraft.lastFMSecret.isEmpty)
                    Button("I Authorized PresenceFM") { Task { await model.completeLastFMAuthorization() } }
                }
                Button("Save Last.fm Credentials") { Task { await model.saveCredentials() } }.presenceButton(prominent: true)
            }
            Section("Advanced") {
                DisclosureGroup("Custom application credentials", isExpanded: $showAdvancedCredentials) {
                    SecureField("Discord Application ID", text: $model.credentialDraft.discordApplicationID)
                    Text("The override is stored in PresenceFM's private local settings. Leave it empty to use the official PresenceFM Discord application.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Save Discord Override") { Task { await model.saveCredentials() } }.presenceButton(prominent: true)
                }
            }
        }.formStyle(.grouped).navigationTitle("Settings")
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var discordEnabled = false
    @State private var lastFMEnabled = false
    @State private var launchAtLogin = false

    private let steps = ["Welcome", "Apple Music", "Discord", "Last.fm", "Privacy", "Startup", "Notifications", "Ready"]

    var body: some View {
        @Bindable var model = model
        @Bindable var preferences = model.preferences
        VStack(spacing: 24) {
            HStack { ForEach(steps.indices, id: \.self) { index in Circle().fill(index <= step ? Color.accentColor : .secondary.opacity(0.25)).frame(width: 8, height: 8) } }
            Group {
                switch step {
                case 0: IntroStep(title: "Welcome to PresenceFM", symbol: "waveform.circle.fill", text: "Your music, present. Share Apple Music on Discord and preserve your listening history on Last.fm. Nothing is published until you enable it.", branded: true)
                case 1: IntroStep(title: "Apple Music Access", symbol: "music.note", text: "PresenceFM asks macOS for Automation access to read the current track. It never controls playback or edits your library.")
                case 2:
                    VStack(spacing: 16) { IntroStep(title: "Connect Discord", symbol: "bubble.left.and.bubble.right", text: "PresenceFM includes its Discord application configuration. Keep Discord Desktop running, then enable Rich Presence."); Toggle("Enable Rich Presence", isOn: $discordEnabled).disabled(!ReleaseConfiguration.hasDiscordConfiguration); if !ReleaseConfiguration.hasDiscordConfiguration { Text("This development build does not include Discord configuration.").foregroundStyle(.orange) } }
                case 3:
                    VStack(spacing: 16) { IntroStep(title: "Connect Last.fm", symbol: "dot.radiowaves.left.and.right", text: "Enter the API key and shared secret from your Last.fm API account, then authorize PresenceFM."); SecureField("API Key", text: $model.credentialDraft.lastFMAPIKey).textFieldStyle(.roundedBorder); SecureField("Shared Secret", text: $model.credentialDraft.lastFMSecret).textFieldStyle(.roundedBorder); Toggle("Enable scrobbling", isOn: $lastFMEnabled); HStack { Button("Authorize") { Task { await model.beginLastFMAuthorization() } }.disabled(model.credentialDraft.lastFMAPIKey.isEmpty || model.credentialDraft.lastFMSecret.isEmpty); Button("Complete Authorization") { Task { await model.completeLastFMAuthorization() } }.disabled(model.lastFMStatus != .connecting) }; if !model.lastFMUsername.isEmpty { Label("Connected as \(model.lastFMUsername)", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }.frame(maxWidth: 440)
                case 4: IntroStep(title: "Private by Default", symbol: "eye.slash", text: "Private Mode clears Discord presence and suppresses Last.fm updates. You can enable it temporarily from the menu bar at any time.")
                case 5:
                    VStack(spacing: 16) { IntroStep(title: "Start Automatically", symbol: "power", text: "PresenceFM can launch quietly when you log in."); Toggle("Launch at Login", isOn: $launchAtLogin) }
                case 6:
                    VStack(spacing: 16) { IntroStep(title: "Actionable Notifications", symbol: "bell.badge", text: "Notifications are only used for permission loss, expired authorization, or a persistently stuck queue."); Button("Allow Notifications") { Task { await model.requestNotifications() } } }
                default: IntroStep(title: "PresenceFM Is Ready", symbol: "checkmark.circle.fill", text: "Play a song in Apple Music. You can review every connection from the dashboard or menu bar.")
                }
            }.frame(maxWidth: 560, minHeight: 310)
            HStack {
                Button("Back") { step -= 1 }.disabled(step == 0)
                Spacer()
                if step < steps.count - 1 { Button("Continue") { step += 1 }.presenceButton(prominent: true) }
                else { Button("Finish") { model.setDiscordEnabled(discordEnabled); model.setLastFMEnabled(lastFMEnabled && !model.lastFMUsername.isEmpty); preferences.launchAtLogin = launchAtLogin; model.setLaunchAtLogin(launchAtLogin); model.completeOnboarding() }.presenceButton(prominent: true) }
            }
        }.padding(32).frame(width: 700, height: 520).interactiveDismissDisabled()
    }
}

struct IntroStep: View {
    let title: String; let symbol: String; let text: String; var branded = false
    var body: some View {
        VStack(spacing: 18) {
            if branded { BrandMark().frame(width: 76, height: 76) }
            else { Image(systemName: symbol).font(.system(size: 64)).foregroundStyle(.tint) }
            Text(title).font(.largeTitle.bold())
            Text(text).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
    }
}
