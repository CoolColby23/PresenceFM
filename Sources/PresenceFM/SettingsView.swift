import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(UpdateManager.self) private var updateManager
    @State private var category = SettingsCategory.general
    @State private var backupDocument: PresenceFMBackupDocument?
    @State private var showingBackupExporter = false
    @State private var showingBackupImporter = false
    @State private var pendingRestore: PresenceFMBackup?
    @State private var showingRestoreConfirmation = false
    @State private var showingDisconnectConfirmation = false
    @State private var dataStatus = ""

    var body: some View {
        @Bindable var preferences = model.preferences
        VStack(spacing: 0) {
            Picker("Settings Category", selection: $category) {
                ForEach(SettingsCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.symbol).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            Form {
                switch category {
                case .general:
                    GeneralSettingsSections(model: model, updateManager: updateManager)
                case .integrations:
                    DiscordSettingsSection(model: model, preferences: preferences)
                    LastFMSettingsSection(
                        model: model,
                        preferences: preferences,
                        disconnect: { showingDisconnectConfirmation = true }
                    )
                case .players:
                    PlaybackProviderSettingsSection(model: model, preferences: preferences)
                case .data:
                    DataSettingsSections(
                        model: model,
                        preferences: preferences,
                        dataStatus: dataStatus,
                        prepareBackup: prepareBackup,
                        restoreBackup: { showingBackupImporter = true },
                        confirmCloudRestore: {
                            pendingRestore = $0
                            showingRestoreConfirmation = true
                        }
                    )
                case .advanced:
                    AdvancedSettingsSection(model: model)
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("Settings")
        .fileExporter(
            isPresented: $showingBackupExporter,
            document: backupDocument,
            contentType: .presenceFMBackup,
            defaultFilename: "PresenceFM-Backup.presencefmbackup",
            onCompletion: finishBackupExport
        )
        .fileImporter(
            isPresented: $showingBackupImporter,
            allowedContentTypes: [.presenceFMBackup, .json],
            onCompletion: importBackup
        )
        .confirmationDialog(
            "Replace current PresenceFM data?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore and Replace", role: .destructive, action: restorePendingBackup)
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text(
                "PresenceFM will first create an automatic local backup, then replace listening history, queued scrobbles, and non-secret settings. Credentials are never imported."
            )
        }
        .confirmationDialog(
            "Disconnect Last.fm?",
            isPresented: $showingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect Last.fm", role: .destructive, action: disconnectLastFM)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PresenceFM will stop scrobbling and remove the saved Last.fm authorization. Your Last.fm account and listening history are not deleted.")
        }
    }

    private func prepareBackup() {
        do {
            backupDocument = PresenceFMBackupDocument(
                backup: try BackupService.make(store: model.store, preferences: model.preferences)
            )
            showingBackupExporter = true
        } catch { dataStatus = error.localizedDescription }
    }

    private func finishBackupExport(_ result: Result<URL, any Error>) {
        if case .success = result {
            model.preferences.lastBackupAt = .now
            dataStatus = "Backup saved."
        } else if case .failure(let error) = result {
            dataStatus = error.localizedDescription
        }
        backupDocument = nil
    }

    private func importBackup(_ result: Result<URL, any Error>) {
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

    private func restorePendingBackup() {
        guard let pendingRestore else { return }
        do {
            try BackupService.restore(pendingRestore, store: model.store, preferences: model.preferences)
            dataStatus = "Backup restored. Reconnect Last.fm if needed."
        } catch { dataStatus = error.localizedDescription }
        self.pendingRestore = nil
    }

    private func disconnectLastFM() {
        model.preferences.lastFMEnabled = false
        Task { await model.disconnectLastFM() }
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case integrations = "Sharing"
    case players = "Players"
    case data = "Data"
    case advanced = "Advanced"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .general: "gear"
        case .integrations: "antenna.radiowaves.left.and.right"
        case .players: "music.note.list"
        case .data: "externaldrive"
        case .advanced: "slider.horizontal.3"
        }
    }
}

private struct GeneralSettingsSections: View {
    let model: AppModel
    let updateManager: UpdateManager

    var body: some View {
        @Bindable var preferences = model.preferences
        @Bindable var updateManager = updateManager
        Section("General") {
            Toggle("Launch PresenceFM at login", isOn: $preferences.launchAtLogin)
                .onChange(of: preferences.launchAtLogin) { _, value in model.setLaunchAtLogin(value) }
            Button("Run Onboarding Again") { model.onboardingPresented = true }
        }
        Section("Demo Mode") {
            Toggle("Simulate playback for a product tour", isOn: demoModeBinding)
            Text(
                "Runs short sample tracks through the real now-playing and local-history pipeline. Discord and Last.fm publishing are paused, and sample history is removed when the demo ends."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        Section("Updates") {
            Toggle("Automatically check for updates", isOn: $updateManager.automaticallyChecksForUpdates)
            Toggle("Automatically download updates", isOn: $updateManager.automaticallyDownloadsUpdates)
                .disabled(!updateManager.automaticallyChecksForUpdates)
            HStack {
                Button("Check for Updates…") { updateManager.checkForUpdates() }
                Spacer()
                Text("Version \(ReleaseConfiguration.version) (\(ReleaseConfiguration.build))")
                    .foregroundStyle(.secondary)
            }
            Text("Updates are downloaded from official PresenceFM GitHub releases and verified before installation.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var demoModeBinding: Binding<Bool> {
        Binding(get: { model.demoModeEnabled }, set: { model.setDemoModeEnabled($0) })
    }
}

private struct LastFMSettingsSection: View {
    let model: AppModel
    let preferences: Preferences
    let disconnect: () -> Void

    var body: some View {
        @Bindable var model = model
        @Bindable var preferences = preferences
        Section("Last.fm") {
            SecureField("API Key", text: $model.credentialDraft.lastFMAPIKey)
            SecureField("Shared Secret", text: $model.credentialDraft.lastFMSecret)
            Toggle("Enable scrobbling", isOn: $preferences.lastFMEnabled)
                .onChange(of: preferences.lastFMEnabled) { _, value in model.setLastFMEnabled(value) }
            Toggle("Send now playing", isOn: $preferences.sendNowPlaying)
            if !model.lastFMUsername.isEmpty {
                LabeledContent("Connected account", value: model.lastFMUsername)
                Button("Disconnect Last.fm…", role: .destructive, action: disconnect)
            }
            HStack {
                Button("Authorize in Browser") { Task { await model.beginLastFMAuthorization() } }
                    .disabled(
                        !model.hasStoredLastFMCredentials
                            && (model.credentialDraft.lastFMAPIKey.isEmpty
                                || model.credentialDraft.lastFMSecret.isEmpty)
                    )
                Button("I Authorized PresenceFM") { Task { await model.completeLastFMAuthorization() } }
            }
            Button("Save Last.fm Credentials") { Task { await model.saveCredentials() } }
                .presenceButton(prominent: true)
            Text("Blank credential fields keep the saved value. PresenceFM never displays your stored shared secret.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Scrobble Exclusions") {
                TextField(
                    "Artists (one per line or comma-separated)",
                    text: $preferences.excludedScrobbleArtists,
                    axis: .vertical
                )
                TextField(
                    "Albums (one per line or comma-separated)",
                    text: $preferences.excludedScrobbleAlbums,
                    axis: .vertical
                )
                TextField(
                    "Title contains (one term per line or comma-separated)",
                    text: $preferences.excludedScrobbleTitleTerms,
                    axis: .vertical
                )
                ForEach(PlaybackPlatform.allCases) { platform in
                    Toggle("Exclude \(platform.rawValue)", isOn: exclusionBinding(for: platform))
                }
                Text("Exclusions affect Last.fm only. Listening History and Discord remain unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onChange(of: preferences.excludedScrobbleArtists) { _, _ in model.refreshScrobbleRules() }
            .onChange(of: preferences.excludedScrobbleAlbums) { _, _ in model.refreshScrobbleRules() }
            .onChange(of: preferences.excludedScrobbleTitleTerms) { _, _ in model.refreshScrobbleRules() }
            .onChange(of: preferences.excludedScrobblePlatforms) { _, _ in model.refreshScrobbleRules() }
        }
    }

    private func exclusionBinding(for platform: PlaybackPlatform) -> Binding<Bool> {
        Binding(
            get: { preferences.excludedScrobblePlatforms.contains(platform) },
            set: { excluded in
                if excluded {
                    preferences.excludedScrobblePlatforms.insert(platform)
                } else {
                    preferences.excludedScrobblePlatforms.remove(platform)
                }
            }
        )
    }
}

private struct PlaybackProviderSettingsSection: View {
    let model: AppModel
    let preferences: Preferences

    var body: some View {
        Section("Music Players") {
            ForEach(Array(preferences.playbackProviderOrder.enumerated()), id: \.element) { index, provider in
                PlaybackProviderRow(
                    provider: provider,
                    isEnabled: providerBinding(provider),
                    canMoveUp: index > 0,
                    canMoveDown: index < preferences.playbackProviderOrder.count - 1,
                    moveUp: { model.movePlaybackProvider(provider, by: -1) },
                    moveDown: { model.movePlaybackProvider(provider, by: 1) }
                )
            }
            if preferences.enabledPlaybackProviders.contains(.youtubeMusic) {
                Button(model.ytmDesktopStatus == .connected ? "Disconnect YTMDesktop" : "Connect YTMDesktop") {
                    Task {
                        if model.ytmDesktopStatus == .connected {
                            await model.disconnectYTMDesktop()
                        } else {
                            await model.connectYTMDesktop()
                        }
                    }
                }
            }
            Text(
                "PresenceFM keeps an actively playing provider selected. When multiple players start together, the order above wins. TIDAL is best effort through macOS Now Playing; YTMDesktop requires its Companion Server."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func providerBinding(_ provider: PlaybackProviderID) -> Binding<Bool> {
        Binding(
            get: { preferences.enabledPlaybackProviders.contains(provider) },
            set: { model.setPlaybackProvider(provider, enabled: $0) }
        )
    }
}

private struct PlaybackProviderRow: View {
    let provider: PlaybackProviderID
    @Binding var isEnabled: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack {
            Toggle(provider.displayName, isOn: $isEnabled)
            Spacer()
            Button(action: moveUp) { Image(systemName: "chevron.up") }
                .labelStyle(.iconOnly)
                .disabled(!canMoveUp)
                .accessibilityLabel(provider.moveEarlierAccessibilityLabel)
                .accessibilityIdentifier("players.\(provider.rawValue).move-up")
            Button(action: moveDown) { Image(systemName: "chevron.down") }
                .labelStyle(.iconOnly)
                .disabled(!canMoveDown)
                .accessibilityLabel(provider.moveLaterAccessibilityLabel)
                .accessibilityIdentifier("players.\(provider.rawValue).move-down")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("players.\(provider.rawValue)")
    }
}

private struct DataSettingsSections: View {
    let model: AppModel
    let preferences: Preferences
    let dataStatus: String
    let prepareBackup: () -> Void
    let restoreBackup: () -> Void
    let confirmCloudRestore: (PresenceFMBackup) -> Void
    @State private var cloudPassphrase = ""
    @State private var cloudStatus = ""
    @State private var cloudOperationInProgress = false

    var body: some View {
        @Bindable var preferences = preferences
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
        Section("Backup and Restore") {
            HStack {
                Button("Back Up PresenceFM…", systemImage: "externaldrive.badge.plus", action: prepareBackup)
                Button("Restore Backup…", systemImage: "arrow.counterclockwise", action: restoreBackup)
            }
            if let date = preferences.lastBackupAt {
                LabeledContent("Last backup", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if !dataStatus.isEmpty { Text(dataStatus).foregroundStyle(.secondary) }
            Text(
                "Backups contain listening history, the scrobble queue, and non-secret settings. Credentials, authorization tokens, diagnostics, artwork, and machine-specific paths are excluded. Restore replaces current local data and disconnects Last.fm."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        Section("Encrypted iCloud Backup") {
            SecureField("Backup passphrase", text: $cloudPassphrase)
                .textContentType(.newPassword)
            HStack {
                Button("Back Up to iCloud", systemImage: "icloud.and.arrow.up") { createCloudBackup() }
                Button("Restore from iCloud", systemImage: "icloud.and.arrow.down") { restoreCloudBackup() }
            }
            .disabled(cloudOperationInProgress || cloudPassphrase.count < 12)
            if cloudOperationInProgress { ProgressView().controlSize(.small) }
            if !cloudStatus.isEmpty { Text(cloudStatus).foregroundStyle(.secondary) }
            Text(
                "Backups use authenticated AES-256-GCM encryption. Your passphrase is never stored and cannot be recovered. iCloud Drive requires an entitled PresenceFM build."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func createCloudBackup() {
        do {
            let data = try BackupService.encode(
                BackupService.make(store: model.store, preferences: preferences)
            )
            let passphrase = cloudPassphrase
            cloudOperationInProgress = true
            cloudStatus = "Encrypting backup…"
            Task {
                do {
                    let url = try await Task.detached {
                        try ICloudBackupStore.save(
                            SecureBackupService.encrypt(data, passphrase: passphrase)
                        )
                    }.value
                    preferences.lastBackupAt = .now
                    cloudStatus = "Encrypted backup saved to iCloud Drive as \(url.lastPathComponent)."
                } catch { cloudStatus = error.localizedDescription }
                cloudOperationInProgress = false
            }
        } catch { cloudStatus = error.localizedDescription }
    }

    private func restoreCloudBackup() {
        let passphrase = cloudPassphrase
        cloudOperationInProgress = true
        cloudStatus = "Downloading and decrypting backup…"
        Task {
            do {
                let backup = try await Task.detached {
                    let encrypted = try ICloudBackupStore.loadLatest()
                    let data = try SecureBackupService.decrypt(encrypted, passphrase: passphrase)
                    let backup = try BackupService.decode(data)
                    try BackupService.validate(backup)
                    return backup
                }.value
                cloudStatus = "Backup decrypted. Confirm restore to continue."
                confirmCloudRestore(backup)
            } catch { cloudStatus = error.localizedDescription }
            cloudOperationInProgress = false
        }
    }
}

private struct AdvancedSettingsSection: View {
    let model: AppModel
    @State private var showingCredentials = false

    var body: some View {
        @Bindable var model = model
        Section("Advanced") {
            DisclosureGroup("Custom application credentials", isExpanded: $showingCredentials) {
                SecureField("Discord Application ID", text: $model.credentialDraft.discordApplicationID)
                Text("The override is stored in PresenceFM's private local settings. Leave it empty to use the official PresenceFM Discord application.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Save Discord Override") { Task { await model.saveCredentials() } }
                    .presenceButton(prominent: true)
            }
        }
    }
}
