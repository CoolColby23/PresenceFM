import AppKit
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $model.selectedSection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
                    .accessibilityIdentifier("dashboard.section.\(section.id.rawValue)")
            }
            .accessibilityIdentifier("dashboard.navigation")
            .navigationTitle("PresenceFM")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom) {
                SidebarPrivacyControl()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        } detail: {
            Group {
                switch model.selectedSection {
                case .nowPlaying: NowPlayingView()
                case .history: ListeningHistoryView()
                case .queue: QueueView()
                case .diagnostics: DiagnosticsView()
                case .settings: SettingsView()
                }
            }.environment(model)
        }
        .task { model.start() }
        .sheet(isPresented: $model.onboardingPresented) { OnboardingView().environment(model) }
        .safeAreaInset(edge: .top) {
            if let issue = model.persistenceIssue {
                PersistenceRecoveryBanner(message: issue)
            }
        }
    }
}

struct NowPlayingView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                if model.demoModeEnabled {
                    HStack(spacing: 14) {
                        Label("Demo playback is active — Discord and Last.fm publishing are paused", systemImage: "testtube.2")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(BrandColors.electricBlue)
                        Spacer()
                        Button("End Demo") { model.setDemoModeEnabled(false) }
                    }
                    .padding(14)
                    .presenceCard()
                    .frame(maxWidth: 820)
                    .accessibilityElement(children: .contain)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 34) {
                        ArtworkView(
                            data: model.artworkData,
                            size: 260,
                            accessibilityDescription: artworkAccessibilityDescription
                        )
                        nowPlayingDetails
                            .frame(minWidth: 380, maxWidth: 520, alignment: .leading)
                    }
                    VStack(spacing: 24) {
                        ArtworkView(
                            data: model.artworkData,
                            size: 200,
                            accessibilityDescription: artworkAccessibilityDescription
                        )
                        nowPlayingDetails
                            .frame(maxWidth: 520, alignment: .leading)
                    }
                }
                .frame(maxWidth: 820)
                Divider()
                VStack(spacing: 0) {
                    ServiceHealthRow(
                        title: model.playbackServiceName,
                        detail: "Playback detection",
                        symbol: "music.note",
                        status: model.musicStatus,
                        statusLabelOverride: nil,
                        recoveryTitle: model.musicStatus == .awaitingPermission ? "Open Settings" : nil,
                        recoveryAction: model.openAutomationSettings
                    )
                    Divider()
                    ServiceHealthRow(
                        title: "Discord",
                        detail: "Rich Presence",
                        symbol: "bubble.left.and.bubble.right",
                        status: model.discordStatus,
                        statusLabelOverride: model.demoModeEnabled ? "Paused for demo" : nil,
                        recoveryTitle: discordRecoveryTitle,
                        recoveryAction: model.refreshDiscord
                    )
                    Divider()
                    ServiceHealthRow(
                        title: "Last.fm",
                        detail: "Scrobbling",
                        symbol: "dot.radiowaves.left.and.right",
                        status: model.lastFMStatus,
                        statusLabelOverride: model.demoModeEnabled ? "Paused for demo" : nil,
                        recoveryTitle: lastFMRecoveryTitle,
                        recoveryAction: { model.selectedSection = .settings }
                    )
                }
                .frame(maxWidth: 820)
            }.padding(36).frame(maxWidth: .infinity)
        }.navigationTitle("Now Playing")
    }

    private var nowPlayingDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(playbackLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(model.snapshot.track?.title ?? "Nothing Playing")
                .font(.largeTitle.bold())
                .lineLimit(2)
            Text(metadataLabel)
                .font(.title2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let track = model.snapshot.track {
                if track.supportsFiniteProgress {
                    PlaybackProgress(position: model.snapshot.position, duration: track.duration)
                }
                ScrobbleProgress(state: model.scrobblePresentation)
                if let url = track.appleMusicURL {
                    Link("Open in \(track.platform.rawValue)", destination: url).presenceButton()
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if model.demoModeEnabled {
                        Text("Starting safe demo playback…")
                    } else {
                        Text("Play something in a supported music app and PresenceFM will pick it up automatically.")
                        Text("Apple Music · Spotify · YouTube Music · TIDAL")
                            .font(.callout.weight(.medium))
                        Button("Start Demo Playback", systemImage: "play.fill") {
                            model.setDemoModeEnabled(true)
                        }
                        .presenceButton(prominent: true)
                        .help("Try PresenceFM without a music app or service account")
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var playbackLabel: String {
        switch model.snapshot.state { case .playing: "Now playing"; case .paused: "Paused"; case .stopped: "PresenceFM is ready" }
    }

    private var metadataLabel: String {
        guard let track = model.snapshot.track else { return "Waiting for playback" }
        return "\(track.artist)\(track.album.map { " • \($0)" } ?? "")"
    }

    private var artworkAccessibilityDescription: String {
        guard let track = model.snapshot.track else { return "Album artwork unavailable" }
        return model.artworkData == nil ? "Album artwork unavailable for \(track.title)" : "Album artwork for \(track.title)"
    }

    private var discordRecoveryTitle: String? {
        guard model.preferences.discordEnabled else { return nil }
        return model.discordStatus.isConnected || model.discordStatus == .connecting ? nil : "Reconnect"
    }

    private var lastFMRecoveryTitle: String? {
        guard model.preferences.lastFMEnabled else { return nil }
        return model.lastFMStatus.isConnected || model.lastFMStatus == .connecting ? nil : "Review Settings"
    }
}

struct ArtworkView: View {
    let data: Data?
    let size: CGFloat
    var accessibilityDescription: String? = nil
    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    BrandMark().padding(size * 0.22)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.1))
        .overlay { RoundedRectangle(cornerRadius: size * 0.1).stroke(.white.opacity(0.12)) }
        .shadow(color: .black.opacity(0.22), radius: size * 0.08, y: size * 0.04)
        .accessibilityLabel(accessibilityDescription ?? (data == nil ? "Album artwork unavailable" : "Album artwork"))
    }
}

struct PlaybackProgress: View {
    let position: TimeInterval
    let duration: TimeInterval
    var body: some View {
        VStack(spacing: 6) {
            ProgressView(value: min(max(position, 0), duration), total: max(duration, 1))
                .tint(BrandColors.electricBlue)
                .accessibilityLabel("Playback progress")
                .accessibilityValue(
                    "\(position.formattedDuration) elapsed, \(max(0, duration - position).formattedDuration) remaining"
                )
            HStack {
                Text(position.formattedDuration)
                Spacer()
                Text("−\(max(0, duration - position).formattedDuration)")
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

struct ScrobbleProgress: View {
    let state: ScrobblePresentationState?
    var body: some View {
        if let state {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(state.label, systemImage: symbol(for: state)).font(.subheadline.weight(.semibold))
                    Spacer()
                    if case .listening(_, let remaining) = state { Text("\(remaining.formattedDuration) to go").font(.caption).foregroundStyle(.secondary) }
                }
                switch state {
                case .listening(let progress, _): ProgressView(value: progress).tint(BrandColors.electricBlue)
                case .ineligible(let reason): Text(reason).font(.caption).foregroundStyle(.secondary)
                default: EmptyView()
                }
            }.padding(14).presenceCard()
        }
    }

    private func symbol(for state: ScrobblePresentationState) -> String {
        switch state { case .ineligible: "nosign"; case .listening: "waveform"; case .ready: "checkmark.circle"; case .queued: "tray"; case .submitted: "checkmark.circle.fill" }
    }
}

struct StatusCapsule: View {
    let title: String; let status: ServiceStatus
    var body: some View {
        Label("\(title): \(status.label)", systemImage: status.isConnected ? "checkmark.circle.fill" : "circle.dashed")
            .font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 8)
            .presenceCard(capsule: true)
    }
}

struct ServiceHealthRow: View {
    let title: String
    let detail: String
    let symbol: String
    let status: ServiceStatus
    let statusLabelOverride: String?
    let recoveryTitle: String?
    let recoveryAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(BrandColors.electricBlue)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ServiceStatusIndicator(status: status, labelOverride: statusLabelOverride)
                Text(statusLabelOverride ?? status.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(statusLabelOverride ?? status.label)")
            if let recoveryTitle {
                Button(recoveryTitle, action: recoveryAction)
                    .accessibilityHint("Attempts to recover the \(title) connection")
            }
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
    }
}

private struct ServiceStatusIndicator: View {
    let status: ServiceStatus
    let labelOverride: String?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var color: Color {
        if labelOverride != nil { return BrandColors.neutral }
        return switch status {
        case .connected: BrandColors.success
        case .connecting, .awaitingPermission, .authorizationExpired: BrandColors.warning
        case .failed: BrandColors.error
        case .disabled, .inactive, .offline: BrandColors.neutral
        }
    }
}

struct SidebarPrivacyControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.isPrivate ? "Private Mode is on" : "Go Private", systemImage: model.isPrivate ? "eye.slash.fill" : "eye.slash")
                .font(.headline)
            Text(model.isPrivate ? privateDetail : "Pause Discord sharing and Last.fm updates at any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PrivacyControls()
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
    }

    private var privateDetail: String {
        if let until = model.privateUntil { return "Sharing is paused until \(until.formatted(date: .omitted, time: .shortened))." }
        return "Sharing and scrobbling are paused until you resume them."
    }
}

struct PrivacyControls: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack {
            if model.isPrivate {
                VStack(alignment: .leading, spacing: 4) {
                    Button("End Private Mode", systemImage: "eye") { model.endPrivateMode() }.presenceButton(prominent: true)
                    if let until = model.privateUntil {
                        Text("Private until \(until, style: .time)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Menu("Go Private", systemImage: "eye.slash") {
                    Button("For 15 Minutes") { model.setPrivate(until: .now.addingTimeInterval(900)) }
                    Button("For 1 Hour") { model.setPrivate(until: .now.addingTimeInterval(3600)) }
                    Button("Until Resumed") { model.setPrivate(until: nil) }
                }.presenceButton()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.isPrivate ? "Private Mode controls" : "Privacy controls")
    }
}

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ArtworkView(data: model.artworkData, size: 68)
                VStack(alignment: .leading) {
                    Text(model.snapshot.track?.title ?? "Nothing Playing").font(.headline).lineLimit(1)
                    Text(model.snapshot.track?.artist ?? "Choose a connected music app").foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if let track = model.snapshot.track {
                if track.supportsFiniteProgress {
                    PlaybackProgress(position: model.snapshot.position, duration: track.duration)
                }
                ScrobbleProgress(state: model.scrobblePresentation)
            }
            VStack(spacing: 8) {
                CompactStatus(name: model.playbackServiceName, status: model.musicStatus, statusLabelOverride: nil)
                CompactStatus(name: "Discord", status: model.discordStatus, statusLabelOverride: model.demoModeEnabled ? "Paused for demo" : nil)
                CompactStatus(name: "Last.fm", status: model.lastFMStatus, statusLabelOverride: model.demoModeEnabled ? "Paused for demo" : nil)
            }
            PrivacyControls()
            Divider()
            HStack {
                Button("Dashboard") { NSApp.showDashboard(using: openWindow) }
                SettingsLink { Text("Settings") }
                Spacer()
                Button("Quit") { model.shutdown(); NSApp.terminate(nil) }
            }.presenceButton()
        }.padding(18).frame(width: 380).task { model.start() }
    }
}

struct CompactStatus: View {
    let name: String
    let status: ServiceStatus
    let statusLabelOverride: String?
    var body: some View {
        HStack {
            ServiceStatusIndicator(status: status, labelOverride: statusLabelOverride)
                .scaleEffect(0.875)
            Text(name)
            Spacer()
            Text(statusLabelOverride ?? status.label).foregroundStyle(.secondary)
        }
            .font(.caption)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(name), \(statusLabelOverride ?? status.label)")
    }
}

struct RecentActivityView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \ActivityRecord.startedAt, order: .reverse) private var records: [ActivityRecord]
    @State private var searchText = ""
    var body: some View {
        List(filteredRecords) { record in
            HStack(spacing: 12) {
                ArtworkView(data: isCurrent(record) ? (model.artworkData ?? record.artworkData) : record.artworkData, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title).font(.headline)
                    Text(record.album.map { "\(record.artist) • \($0)" } ?? record.artist).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(record.outcomeLabel).foregroundStyle(record.outcomeLabel == "Skipped" ? .secondary : .primary)
                Text(record.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute()).foregroundStyle(.secondary)
            }.padding(.vertical, 3)
        }
        .searchable(text: $searchText, prompt: "Search title, artist, or album")
        .navigationTitle("Recent Activity")
        .overlay { if filteredRecords.isEmpty { ContentUnavailableView(searchText.isEmpty ? "No Activity Yet" : "No Matches", systemImage: "clock", description: Text(searchText.isEmpty ? "Played tracks will appear here." : "Try a different search.")) } }
    }

    private var filteredRecords: [ActivityRecord] {
        guard !searchText.isEmpty else { return records }
        return records.filter { [$0.title, $0.artist, $0.album ?? ""].contains { $0.localizedCaseInsensitiveContains(searchText) } }
    }

    private func isCurrent(_ record: ActivityRecord) -> Bool {
        record.title == model.snapshot.track?.title && record.artist == model.snapshot.track?.artist
    }
}

struct QueueView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \ScrobbleRecord.startedAt, order: .reverse) private var records: [ScrobbleRecord]
    @State private var pendingRemoval: QueueRemoval?
    var body: some View {
        VStack(spacing: 0) {
            if let commonError {
                QueueRecoveryBanner(
                    count: queuedRecords.count,
                    message: commonError,
                    action: { model.selectedSection = .settings }
                )
                Divider()
            }
            List {
                ForEach(queuedRecords) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.title).font(.headline)
                            Text(record.artist).foregroundStyle(.secondary)
                            if let error = record.lastError, error != commonError {
                                Text(error).font(.caption).foregroundStyle(BrandColors.error)
                            }
                        }
                        Spacer()
                        Text(record.stateRaw.queueDisplayName).foregroundStyle(.secondary)
                        Menu("Actions", systemImage: "ellipsis.circle") {
                            if record.state == .permanentlyFailed { Button("Retry") { model.retryScrobble(id: record.id) } }
                            Button("Remove…", role: .destructive) { requestRemoval(of: record) }
                        }
                        .menuIndicator(.hidden)
                        .accessibilityLabel("Actions for \(record.title)")
                    }
                    .contextMenu {
                        if record.state == .permanentlyFailed { Button("Retry") { model.retryScrobble(id: record.id) } }
                        Button("Remove…", role: .destructive) { requestRemoval(of: record) }
                    }
                }
            }
            .accessibilityIdentifier("queue.list")
        }
        .navigationTitle("Scrobble Queue")
        .overlay {
            if queuedRecords.isEmpty {
                ContentUnavailableView("Queue Is Clear", systemImage: "checkmark.circle", description: Text("Offline scrobbles will wait here."))
            }
        }
        .confirmationDialog(
            "Remove this queued scrobble?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { removal in
            Button("Remove \(removal.title)", role: .destructive) {
                model.removeScrobble(id: removal.id)
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { removal in
            Text("This removes “\(removal.title)” from the local retry queue. It cannot be submitted to Last.fm afterward.")
        }
    }

    private var queuedRecords: [ScrobbleRecord] { records.filter { $0.state != .submitted } }

    private var commonError: String? {
        let errors = queuedRecords.compactMap(\.lastError)
        guard let first = errors.first, errors.count == queuedRecords.count, errors.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private func requestRemoval(of record: ScrobbleRecord) {
        pendingRemoval = QueueRemoval(id: record.id, title: record.title)
    }
}

private struct QueueRemoval: Identifiable {
    let id: UUID
    let title: String
}

private struct QueueRecoveryBanner: View {
    let count: Int
    let message: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandColors.warning)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(count) \(count == 1 ? "scrobble needs" : "scrobbles need") attention")
                    .font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Review Last.fm Settings", action: action)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(BrandColors.warning.opacity(0.08))
        .accessibilityElement(children: .contain)
    }
}

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \DiagnosticRecord.timestamp, order: .reverse) private var records: [DiagnosticRecord]
    @Query(sort: \IntegrationHealthEvent.timestamp, order: .reverse) private var healthEvents: [IntegrationHealthEvent]
    var body: some View {
        Form {
            Section("System") { LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString); LabeledContent("App Version", value: ReleaseConfiguration.version) }
            Section("Services") {
                ForEach(model.integrationHealth) { health in
                    LabeledContent(health.integration.displayName, value: health.summary)
                        .accessibilityLabel("\(health.integration.displayName), \(health.summary)")
                }
            }
            Section("Playback Polling") {
                LabeledContent("Latest poll", value: model.playbackPollMetrics.totalDuration.formatted(.number.precision(.fractionLength(1...1))) + " s")
                ForEach(PlaybackProviderID.allCases) { provider in
                    if let duration = model.playbackPollMetrics.providerDurations[provider] {
                        LabeledContent(provider.displayName, value: "\(Int((duration * 1_000).rounded())) ms")
                    }
                }
                Text("Use the PlaybackPolling signposts in Instruments to measure sustained CPU, latency, and energy in a release build.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Recovery") {
                if model.musicStatus == .awaitingPermission { Button("Open Automation Privacy Settings") { model.openAutomationSettings() } }
                if model.preferences.discordEnabled { Button("Reconnect to Discord") { model.refreshDiscord() } }
                if model.lastFMStatus == .authorizationExpired { Button("Reconnect Last.fm") { model.selectedSection = .settings } }
            }
            Section("Support Report") {
                Button("Copy Redacted Support Report", systemImage: "doc.on.doc") { model.copyDiagnosticReport() }
                Text(model.diagnosticCopyStatus.isEmpty ? "Includes app, macOS, connection status, and the latest redacted diagnostic messages. It excludes credentials and listening metadata." : model.diagnosticCopyStatus)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Redacted Log") { ForEach(records.prefix(50)) { record in Text("[\(record.category)] \(record.message)").font(.caption.monospaced()) } }
            Section("Local Integration Health") {
                if healthEvents.isEmpty { Text("No integration state changes recorded yet.").foregroundStyle(.secondary) }
                ForEach(healthEvents.prefix(50)) { event in
                    HStack {
                        Text(IntegrationID(rawValue: event.integrationRaw)?.displayName ?? "Integration")
                        Spacer()
                        Text(IntegrationState(rawValue: event.stateRaw)?.rawValue.capitalized ?? event.stateRaw.capitalized)
                        Text(event.timestamp, style: .relative).foregroundStyle(.secondary)
                    }.font(.caption)
                }
                Text("This bounded local history stores only integration state and timestamps—never track metadata, usernames, or credentials.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).navigationTitle("Diagnostics")
    }
}

private struct PersistenceRecoveryBanner: View {
    @Environment(AppModel.self) private var model
    let message: String
    @State private var confirmingEmptySession = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(BrandColors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Local data needs recovery").font(.headline)
                Text(message).font(.caption).lineLimit(3)
            }
            Spacer()
            if model.usingTemporaryStore {
                Button("Restore Database Backup") { model.restoreLatestDatabaseBackup() }
                Button("Start Fresh…") { confirmingEmptySession = true }
                Button("Restart PresenceFM") { model.restartApplication() }
            } else {
                Button("Open Data Settings") { model.selectedSection = .settings }
                Button("Dismiss") { model.persistenceIssue = nil }
            }
        }
        .padding(12).background(.bar)
        .accessibilityElement(children: .contain)
        .overlay(alignment: .bottomLeading) {
            if !model.persistenceRecoveryStatus.isEmpty {
                Text(model.persistenceRecoveryStatus).font(.caption).foregroundStyle(.secondary).padding(.leading, 42).offset(y: 11)
            }
        }
        .confirmationDialog("Start with a new local database?", isPresented: $confirmingEmptySession, titleVisibility: .visible) {
            Button("Preserve Failed Store and Start Fresh", role: .destructive) { model.prepareFreshDatabase() }
        } message: {
            Text("PresenceFM will move the failed database into a recovery folder and create a new store after restart. It will not delete the failed data.")
        }
    }
}

private extension TimeInterval {
    var formattedDuration: String {
        let total = max(0, Int(self.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private extension String {
    var queueDisplayName: String {
        switch self { case "permanentlyFailed": "Needs attention"; case "retrying": "Retrying"; case "pending": "Waiting"; default: capitalized }
    }
}

#Preview("Playing") {
    let store = try! PersistenceStore(inMemory: true)
    let model = AppModel(store: store)
    let track = TrackMetadata(
        identity: .init(persistentID: "preview"), title: "Midnight Signal", artist: "Presence FM",
        album: "Afterglow", duration: 246, source: .appleMusicCatalog,
        appleMusicURL: URL(string: "https://music.apple.com"), artworkReference: nil
    )
    model.snapshot = .init(track: track, state: .playing, position: 92, observedAt: .now, confidence: .high)
    model.activeSession = .init(id: UUID(), track: track, startedAt: .now.addingTimeInterval(-92), accumulatedPlayTime: 82, lastPosition: 92, eligibility: .listening, outcome: .active)
    model.musicStatus = .connected
    model.discordStatus = .connected
    model.lastFMStatus = .connected
    return NowPlayingView().environment(model).modelContainer(store.container).frame(width: 900, height: 650)
}

#Preview("Permission Required") {
    let store = try! PersistenceStore(inMemory: true)
    let model = AppModel(store: store)
    model.musicStatus = .awaitingPermission
    model.discordStatus = .offline
    model.lastFMStatus = .authorizationExpired
    return NowPlayingView().environment(model).modelContainer(store.container).frame(width: 900, height: 650)
}
