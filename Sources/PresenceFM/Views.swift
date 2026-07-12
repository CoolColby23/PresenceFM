import AppKit
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $model.selectedSection) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .navigationTitle("PresenceFM")
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
    }
}

struct NowPlayingView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                HStack(alignment: .center, spacing: 34) {
                    ArtworkView(data: model.artworkData, size: 260)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(playbackLabel).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                        Text(model.snapshot.track?.title ?? "Nothing Playing")
                            .font(.system(size: 38, weight: .bold, design: .rounded)).lineLimit(2)
                        Text(metadataLabel).font(.title2).foregroundStyle(.secondary).lineLimit(2)
                        if let track = model.snapshot.track {
                            PlaybackProgress(position: model.snapshot.position, duration: track.duration)
                            ScrobbleProgress(state: model.scrobblePresentation)
                            if let url = track.appleMusicURL {
                                Link("Open in Apple Music", destination: url).presenceButton()
                            }
                        } else {
                            Text("Start a song in Apple Music to share what you’re listening to.")
                                .foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: 520, alignment: .leading)
                }
                HStack(spacing: 12) {
                    StatusCapsule(title: "Apple Music", status: model.musicStatus)
                    StatusCapsule(title: "Discord", status: model.discordStatus)
                    StatusCapsule(title: "Last.fm", status: model.lastFMStatus)
                }
                PrivacyControls()
            }.padding(36).frame(maxWidth: .infinity)
        }.navigationTitle("Now Playing")
    }

    private var playbackLabel: String {
        switch model.snapshot.state { case .playing: "Now playing"; case .paused: "Paused"; case .stopped: "PresenceFM is ready" }
    }

    private var metadataLabel: String {
        guard let track = model.snapshot.track else { return "Apple Music" }
        return "\(track.artist)\(track.album.map { " • \($0)" } ?? "")"
    }
}

struct ArtworkView: View {
    let data: Data?
    let size: CGFloat
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
        .accessibilityLabel(data == nil ? "Album artwork unavailable" : "Album artwork")
    }
}

struct PlaybackProgress: View {
    let position: TimeInterval
    let duration: TimeInterval
    var body: some View {
        VStack(spacing: 6) {
            ProgressView(value: min(max(position, 0), duration), total: max(duration, 1))
                .tint(BrandColors.electricBlue).accessibilityLabel("Playback progress")
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
                case .listening(let progress, _): ProgressView(value: progress).tint(BrandColors.magenta)
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
                    Text(model.snapshot.track?.artist ?? "Apple Music").foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if let track = model.snapshot.track {
                PlaybackProgress(position: model.snapshot.position, duration: track.duration)
                ScrobbleProgress(state: model.scrobblePresentation)
            }
            VStack(spacing: 8) {
                CompactStatus(name: "Apple Music", status: model.musicStatus)
                CompactStatus(name: "Discord", status: model.discordStatus)
                CompactStatus(name: "Last.fm", status: model.lastFMStatus)
            }
            PrivacyControls()
            Divider()
            HStack {
                Button("Dashboard") { openWindow(id: "dashboard"); NSApp.activate() }
                SettingsLink { Text("Settings") }
                Spacer()
                Button("Quit") { model.shutdown(); NSApp.terminate(nil) }
            }.presenceButton()
        }.padding(18).frame(width: 380).task { model.start() }
    }
}

struct CompactStatus: View {
    let name: String; let status: ServiceStatus
    var body: some View {
        HStack { Circle().fill(status.isConnected ? .green : .secondary).frame(width: 7, height: 7); Text(name); Spacer(); Text(status.label).foregroundStyle(.secondary) }
            .font(.caption)
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
    var body: some View {
        List {
            ForEach(records.filter { $0.state != .submitted }) { record in
                HStack { VStack(alignment: .leading) { Text(record.title).font(.headline); Text(record.artist).foregroundStyle(.secondary); if let error = record.lastError { Text(error).font(.caption).foregroundStyle(.red) } }; Spacer(); Text(record.stateRaw.queueDisplayName) }
                    .contextMenu {
                        if record.state == .permanentlyFailed { Button("Retry") { model.retryScrobble(id: record.id) } }
                        Button("Remove", role: .destructive) { model.removeScrobble(id: record.id) }
                    }
            }
        }.navigationTitle("Scrobble Queue").overlay { if records.allSatisfy({ $0.state == .submitted }) { ContentUnavailableView("Queue Is Clear", systemImage: "checkmark.circle", description: Text("Offline scrobbles will wait here.")) } }
    }
}

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \DiagnosticRecord.timestamp, order: .reverse) private var records: [DiagnosticRecord]
    var body: some View {
        Form {
            Section("System") { LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString); LabeledContent("App Version", value: ReleaseConfiguration.version) }
            Section("Services") { LabeledContent("Apple Music", value: model.musicStatus.label); LabeledContent("Discord", value: model.discordStatus.label); LabeledContent("Last.fm", value: model.lastFMStatus.label) }
            Section("Recovery") {
                if model.musicStatus == .awaitingPermission { Button("Open Automation Privacy Settings") { model.openAutomationSettings() } }
                if model.preferences.discordEnabled { Button("Reconnect to Discord") { model.refreshDiscord() } }
                if model.lastFMStatus == .authorizationExpired { Button("Reconnect Last.fm") { model.selectedSection = .settings } }
            }
            Section("Redacted Log") { ForEach(records.prefix(50)) { record in Text("[\(record.category)] \(record.message)").font(.caption.monospaced()) } }
        }.formStyle(.grouped).navigationTitle("Diagnostics")
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
