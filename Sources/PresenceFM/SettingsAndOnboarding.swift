import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showAdvancedCredentials = false
    @State private var backupDocument: PresenceFMBackupDocument?
    @State private var showingBackupExporter = false
    @State private var showingBackupImporter = false
    @State private var pendingRestore: PresenceFMBackup?
    @State private var showingRestoreConfirmation = false
    @State private var showingDisconnectConfirmation = false
    @State private var dataStatus = ""

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
            Section("Data") {
                HStack {
                    Button("Back Up PresenceFM…", systemImage: "externaldrive.badge.plus") { prepareBackup() }
                    Button("Restore Backup…", systemImage: "arrow.counterclockwise") { showingBackupImporter = true }
                }
                if let date = preferences.lastBackupAt {
                    LabeledContent("Last backup", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                if !dataStatus.isEmpty { Text(dataStatus).foregroundStyle(.secondary) }
                Text("Backups contain listening history, the scrobble queue, and non-secret settings. Credentials, authorization tokens, diagnostics, artwork, and machine-specific paths are excluded. Restore replaces current local data and disconnects Last.fm.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Discord") {
                Toggle("Enable Discord Rich Presence", isOn: $preferences.discordEnabled).onChange(of: preferences.discordEnabled) { _, value in model.setDiscordEnabled(value) }
                Toggle("Show album", isOn: $preferences.showAlbum).onChange(of: preferences.showAlbum) { _, _ in model.refreshPresenceOptions() }
                Toggle("Show timer", isOn: $preferences.showTimer).onChange(of: preferences.showTimer) { _, _ in model.refreshPresenceOptions() }
                Toggle("Show listening link", isOn: $preferences.showLink).onChange(of: preferences.showLink) { _, _ in model.refreshPresenceOptions() }
                Picker("First line", selection: $preferences.discordLineOne) {
                    ForEach(DiscordLineFormat.allCases) { Text($0.rawValue).tag($0) }
                }.onChange(of: preferences.discordLineOne) { _, _ in model.refreshPresenceOptions() }
                if preferences.discordLineOne == .custom {
                    TextField("First line template", text: $preferences.discordCustomLineOne)
                        .onSubmit { model.refreshPresenceOptions() }
                }
                Picker("Second line", selection: $preferences.discordLineTwo) {
                    ForEach(DiscordLineFormat.allCases) { Text($0.rawValue).tag($0) }
                }.onChange(of: preferences.discordLineTwo) { _, _ in model.refreshPresenceOptions() }
                if preferences.discordLineTwo == .custom {
                    TextField("Second line template", text: $preferences.discordCustomLineTwo)
                        .onSubmit { model.refreshPresenceOptions() }
                }
                if preferences.discordLineOne == .custom || preferences.discordLineTwo == .custom {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available tokens: {title}, {artist}, {album}, {platform}")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Preview") .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(discordPreview(preferences.discordLineOne, custom: preferences.discordCustomLineOne))
                        Text(discordPreview(preferences.discordLineTwo, custom: preferences.discordCustomLineTwo))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: .rect(cornerRadius: 8))
                }
                Picker("Small image", selection: $preferences.discordSmallImage) {
                    ForEach(DiscordSmallImage.allCases) { Text($0.rawValue).tag($0) }
                }.onChange(of: preferences.discordSmallImage) { _, _ in model.refreshPresenceOptions() }
                TextField("Button label", text: $preferences.discordButtonLabel, prompt: Text("Automatic for each platform"))
                    .onSubmit { model.refreshPresenceOptions() }
                Text("Leave the label empty for platform-aware text such as “Listen on Spotify.” Discord limits labels to 32 characters.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Album artwork is paired with your selected platform or PresenceFM badge. The timer displays track progress when duration is available.")
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
                    Button("Disconnect Last.fm…", role: .destructive) { showingDisconnectConfirmation = true }
                }
                HStack {
                    Button("Authorize in Browser") { Task { await model.beginLastFMAuthorization() } }
                        .disabled(!model.hasStoredLastFMCredentials && (model.credentialDraft.lastFMAPIKey.isEmpty || model.credentialDraft.lastFMSecret.isEmpty))
                    Button("I Authorized PresenceFM") { Task { await model.completeLastFMAuthorization() } }
                }
                Button("Save Last.fm Credentials") { Task { await model.saveCredentials() } }.presenceButton(prominent: true)
                Text("Blank credential fields keep the saved value. PresenceFM never displays your stored shared secret.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Music Platforms") {
                Toggle("Apple Music", isOn: playbackProviderBinding(.appleMusic))
                Toggle("Spotify", isOn: playbackProviderBinding(.spotify))
                Toggle("TIDAL — best effort through macOS Now Playing", isOn: playbackProviderBinding(.tidal))
                HStack {
                    Toggle("YouTube Music", isOn: playbackProviderBinding(.youtubeMusic))
                    Spacer()
                    if preferences.enabledPlaybackProviders.contains(.youtubeMusic), model.ytmDesktopStatus == .connected {
                        Button("Disconnect") { Task { await model.disconnectYTMDesktop() } }
                    } else if preferences.enabledPlaybackProviders.contains(.youtubeMusic) {
                        Button("Connect YTMDesktop") { Task { await model.connectYTMDesktop() } }
                    }
                }
                Text("In YTMDesktop 2, enable Companion Server and companion authorization before connecting. PresenceFM only reads local playback state.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Advanced") {
                DisclosureGroup("Custom application credentials", isExpanded: $showAdvancedCredentials) {
                    SecureField("Discord Application ID", text: $model.credentialDraft.discordApplicationID)
                    Text("The override is stored in PresenceFM's private local settings. Leave it empty to use the official PresenceFM Discord application.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Save Discord Override") { Task { await model.saveCredentials() } }.presenceButton(prominent: true)
                }
            }
        }
        .formStyle(.grouped).navigationTitle("Settings")
        .fileExporter(
            isPresented: $showingBackupExporter, document: backupDocument,
            contentType: .presenceFMBackup, defaultFilename: "PresenceFM-Backup.presencefmbackup"
        ) { result in
            if case .success = result { preferences.lastBackupAt = .now; dataStatus = "Backup saved." }
            else if case .failure(let error) = result { dataStatus = error.localizedDescription }
            backupDocument = nil
        }
        .fileImporter(isPresented: $showingBackupImporter, allowedContentTypes: [.presenceFMBackup, .json]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let backup = try BackupService.decode(Data(contentsOf: url))
                try BackupService.validate(backup)
                pendingRestore = backup
                showingRestoreConfirmation = true
            } catch { dataStatus = error.localizedDescription }
        }
        .confirmationDialog(
            "Replace current PresenceFM data?", isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore and Replace", role: .destructive) { restorePendingBackup() }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("PresenceFM will first create an automatic local backup, then replace listening history, queued scrobbles, and non-secret settings. Credentials are never imported.")
        }
        .confirmationDialog(
            "Disconnect Last.fm?", isPresented: $showingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect Last.fm", role: .destructive) {
                preferences.lastFMEnabled = false
                Task { await model.disconnectLastFM() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PresenceFM will stop scrobbling and remove the saved Last.fm authorization. Your Last.fm account and listening history are not deleted.")
        }
    }

    private func discordPreview(_ format: DiscordLineFormat, custom: String) -> String {
        let template = format == .custom ? custom : format.value(title: "Midnight Drive", artist: "The Satellites", album: "Afterglow")
        let rendered = DiscordTemplate.render(template, title: "Midnight Drive", artist: "The Satellites", album: "Afterglow", platform: .appleMusic)
        return rendered.isEmpty ? "Apple Music" : rendered
    }

    private func playbackProviderBinding(_ provider: PlaybackProviderID) -> Binding<Bool> {
        Binding(
            get: { model.preferences.enabledPlaybackProviders.contains(provider) },
            set: { model.setPlaybackProvider(provider, enabled: $0) }
        )
    }

    private func prepareBackup() {
        do {
            backupDocument = PresenceFMBackupDocument(backup: try BackupService.make(store: model.store, preferences: model.preferences))
            showingBackupExporter = true
        } catch { dataStatus = error.localizedDescription }
    }

    private func restorePendingBackup() {
        guard let pendingRestore else { return }
        do {
            try BackupService.restore(pendingRestore, store: model.store, preferences: model.preferences)
            dataStatus = "Backup restored. Reconnect Last.fm if needed."
        } catch { dataStatus = error.localizedDescription }
        self.pendingRestore = nil
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var discordEnabled = false
    @State private var lastFMEnabled = false
    @State private var launchAtLogin = false
    @State private var selectedProviders = Set(PlaybackProviderID.allCases)

    private let steps = ["Welcome", "Music Players", "Discord", "Last.fm", "Privacy", "Startup", "Notifications", "Ready"]

    var body: some View {
        @Bindable var model = model
        @Bindable var preferences = model.preferences
        VStack(spacing: 24) {
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
            Group {
                switch step {
                case 0: IntroStep(title: "Welcome to PresenceFM", symbol: "waveform.circle.fill", text: "Your music, present. Share tracks from your music apps on Discord and preserve your listening history on Last.fm. Nothing is published until you enable it.", branded: true)
                case 1:
                    VStack(spacing: 14) {
                        IntroStep(title: "Choose Your Players", symbol: "music.note", text: "Enable only the local players you use. Apple Music permission is requested only when Apple Music is enabled. YouTube Music requires YTMDesktop's Companion Server; TIDAL uses best-effort macOS Now Playing metadata.")
                        ForEach(PlaybackProviderID.allCases) { provider in
                            Toggle(provider.displayName, isOn: providerBinding(provider)).frame(maxWidth: 360)
                        }
                    }
                case 2:
                    VStack(spacing: 16) { IntroStep(title: "Connect Discord", symbol: "bubble.left.and.bubble.right", text: "PresenceFM includes its Discord application configuration. Keep Discord Desktop running, then enable Rich Presence."); Toggle("Enable Rich Presence", isOn: $discordEnabled).disabled(!ReleaseConfiguration.hasDiscordConfiguration); if !ReleaseConfiguration.hasDiscordConfiguration { Text("This development build does not include Discord configuration.").foregroundStyle(BrandColors.warning) } }
                case 3:
                    VStack(spacing: 16) { IntroStep(title: "Connect Last.fm", symbol: "dot.radiowaves.left.and.right", text: "Enter the API key and shared secret from your Last.fm API account, then authorize PresenceFM."); SecureField("API Key", text: $model.credentialDraft.lastFMAPIKey).textFieldStyle(.roundedBorder); SecureField("Shared Secret", text: $model.credentialDraft.lastFMSecret).textFieldStyle(.roundedBorder); Toggle("Enable scrobbling", isOn: $lastFMEnabled); HStack { Button("Authorize") { Task { await model.beginLastFMAuthorization() } }.disabled(model.credentialDraft.lastFMAPIKey.isEmpty || model.credentialDraft.lastFMSecret.isEmpty); Button("Complete Authorization") { Task { await model.completeLastFMAuthorization() } }.disabled(model.lastFMStatus != .connecting) }; if !model.lastFMUsername.isEmpty { Label("Connected as \(model.lastFMUsername)", systemImage: "checkmark.circle.fill").foregroundStyle(BrandColors.success) } }.frame(maxWidth: 440)
                case 4: IntroStep(title: "Private by Default", symbol: "eye.slash", text: "Private Mode clears Discord presence and suppresses Last.fm updates. You can enable it temporarily from the menu bar at any time.")
                case 5:
                    VStack(spacing: 16) { IntroStep(title: "Start Automatically", symbol: "power", text: "PresenceFM can launch quietly when you log in."); Toggle("Launch at Login", isOn: $launchAtLogin) }
                case 6:
                    VStack(spacing: 16) { IntroStep(title: "Actionable Notifications", symbol: "bell.badge", text: "Notifications are only used for permission loss, expired authorization, or a persistently stuck queue."); Button("Allow Notifications") { Task { await model.requestNotifications() } } }
                default: IntroStep(title: "PresenceFM Is Ready", symbol: "checkmark.circle.fill", text: "Play a song in one of your selected music apps. Optional integrations can be connected or skipped at any time, and every connection has a recovery path in the dashboard.")
                }
            }.frame(maxWidth: 560, minHeight: 310)
            HStack {
                Button("Back") { step -= 1 }.disabled(step == 0).keyboardShortcut(.cancelAction)
                Spacer()
                if step < steps.count - 1 { Button("Continue") { step += 1 }.presenceButton(prominent: true).keyboardShortcut(.defaultAction) }
                else { Button("Finish") { preferences.enabledPlaybackProviders = selectedProviders; model.setDiscordEnabled(discordEnabled); model.setLastFMEnabled(lastFMEnabled && !model.lastFMUsername.isEmpty); preferences.launchAtLogin = launchAtLogin; model.setLaunchAtLogin(launchAtLogin); model.completeOnboarding() }.presenceButton(prominent: true).keyboardShortcut(.defaultAction) }
            }
        }.padding(32).frame(width: 700, height: 520).interactiveDismissDisabled()
    }

    private func providerBinding(_ provider: PlaybackProviderID) -> Binding<Bool> {
        Binding(
            get: { selectedProviders.contains(provider) },
            set: { enabled in
                if enabled { selectedProviders.insert(provider) }
                else { selectedProviders.remove(provider) }
            }
        )
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
