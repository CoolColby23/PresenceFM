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
                case .recent: RecentActivityView()
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
        VStack(spacing: 28) {
            Spacer()
            BrandHero()
            VStack(spacing: 8) {
                Text(model.snapshot.track?.title ?? "Nothing Playing").font(.largeTitle.bold())
                Text(model.snapshot.track.map { "\($0.artist)\($0.album.map { " • \($0)" } ?? "")" } ?? "Start a song in Apple Music")
                    .font(.title3).foregroundStyle(.secondary)
            }
            if let track = model.snapshot.track {
                ProgressView(value: min(model.snapshot.position, track.duration), total: track.duration)
                    .frame(maxWidth: 520).accessibilityLabel("Playback progress")
                Text("\(model.snapshot.confidence.rawValue.capitalized) confidence • \(track.source.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                StatusCapsule(title: "Apple Music", status: model.musicStatus)
                StatusCapsule(title: "Discord", status: model.discordStatus)
                StatusCapsule(title: "Last.fm", status: model.lastFMStatus)
            }
            PrivacyControls()
            Spacer()
        }.padding(36).navigationTitle("Now Playing")
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
                Button("End Private Mode", systemImage: "eye") { model.endPrivateMode() }.presenceButton(prominent: true)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                BrandMark().frame(width: 42, height: 42)
                VStack(alignment: .leading) {
                    Text(model.snapshot.track?.title ?? "Nothing Playing").font(.headline).lineLimit(1)
                    Text(model.snapshot.track?.artist ?? "Apple Music").foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if let track = model.snapshot.track { ProgressView(value: model.snapshot.position, total: track.duration) }
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
        }.padding(18).frame(width: 360).task { model.start() }
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
    @Query(sort: \ActivityRecord.startedAt, order: .reverse) private var records: [ActivityRecord]
    var body: some View {
        List(records) { record in
            HStack { VStack(alignment: .leading) { Text(record.title).font(.headline); Text(record.artist).foregroundStyle(.secondary) }; Spacer(); Text(record.outcomeLabel); Text(record.startedAt, format: .dateTime.hour().minute()) }
        }.navigationTitle("Recent Activity").overlay { if records.isEmpty { ContentUnavailableView("No Activity Yet", systemImage: "clock", description: Text("Played tracks will appear here.")) } }
    }
}

struct QueueView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \ScrobbleRecord.startedAt, order: .reverse) private var records: [ScrobbleRecord]
    var body: some View {
        List {
            ForEach(records.filter { $0.state != .submitted }) { record in
                HStack { VStack(alignment: .leading) { Text(record.title).font(.headline); Text(record.artist).foregroundStyle(.secondary); if let error = record.lastError { Text(error).font(.caption).foregroundStyle(.red) } }; Spacer(); Text(record.stateRaw.capitalized) }
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
            Section("Redacted Log") { ForEach(records.prefix(50)) { record in Text("[\(record.category)] \(record.message)").font(.caption.monospaced()) } }
        }.formStyle(.grouped).navigationTitle("Diagnostics")
    }
}
