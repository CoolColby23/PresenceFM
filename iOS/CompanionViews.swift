import MusicKit
import PresenceFMCore
import SwiftUI

struct CompanionRootView: View {
    let model: CompanionAppModel
    var body: some View {
        TabView {
            NavigationStack { NowPlayingView(model: model) }.tabItem { Label("Now Playing", systemImage: "play.circle.fill") }
            NavigationStack { HistoryView(model: model) }.tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            NavigationStack { ReviewView(model: model) }.tabItem { Label("Review", systemImage: "tray.full.fill") }.badge(model.reviewItems.count)
        }
        .tint(.pink)
        .alert("PresenceFM", isPresented: Binding(get: { model.statusMessage != nil }, set: { if !$0 { model.statusMessage = nil } })) {
            Button("OK") { model.statusMessage = nil }
        } message: {
            Text(model.statusMessage ?? "")
        }
        .sheet(item: Binding(get: { model.presentedEditor }, set: { model.presentedEditor = $0 })) { MetadataEditor(model: model, listen: $0) }
    }
}

struct NowPlayingView: View {
    let model: CompanionAppModel
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if model.musicAuthorization != .authorized {
                    ContentUnavailableView(
                        "Apple Music access needed", systemImage: "music.note", description: Text("PresenceFM reads the Music app's public playback state."))
                    Button("Allow Music Access") { Task { await model.requestMusicAccess() } }.buttonStyle(.borderedProminent)
                } else if let evidence = model.nowPlaying {
                    Image(systemName: "music.note.list").font(.system(size: 64)).foregroundStyle(.pink)
                    Text(evidence.originalMetadata.title).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(evidence.originalMetadata.artist).foregroundStyle(.secondary)
                    ProgressView(value: progress(evidence)).tint(.pink)
                    HStack {
                        Label(evidence.confidence.rawValue.capitalized, systemImage: "waveform"); Spacer(); Text(duration(evidence.observedPlayTime ?? 0))
                    }.font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView(
                        "Nothing playing", systemImage: "music.note",
                        description: Text("Start a song in Apple Music. PresenceFM will observe it while iOS grants runtime."))
                }
                CaptureHealthCard(model: model)
            }.padding()
        }
        .navigationTitle("Now Playing")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CompanionSettingsView(model: model)
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
    }
    private func progress(_ evidence: PlaybackEvidence) -> Double {
        guard let duration = evidence.originalMetadata.duration, duration > 0 else { return 0 };
        return min(1, (evidence.observedPlayTime ?? 0) / min(duration * 0.5, 240))
    }
}

struct CaptureHealthCard: View {
    let model: CompanionAppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Capture health", systemImage: "checkmark.shield").font(.headline)
            LabeledContent("Last.fm", value: model.lastFMUsername ?? "Not connected")
            LabeledContent("iCloud", value: model.cloudStatus)
            LabeledContent("Queued", value: String(model.history.filter { $0.state == .queued }.count))
            if model.snapshot.privateMode { Label("Private Mode is active", systemImage: "eye.slash.fill").foregroundStyle(.orange) }
        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct HistoryView: View {
    let model: CompanionAppModel
    var body: some View {
        List {
            if model.history.isEmpty {
                ContentUnavailableView(
                    "No listening history", systemImage: "clock", description: Text("Observed and reviewed Apple Music listens appear here."))
            }
            ForEach(model.history) { listen in
                ListenRow(listen: listen).swipeActions {
                    if listen.state == .failed || listen.state == .queued { Button("Retry") { Task { await model.approve(listen) } }.tint(.pink) }
                }
            }
        }.navigationTitle("History")
    }
}

struct ReviewView: View {
    let model: CompanionAppModel
    var body: some View {
        List {
            if model.reviewItems.isEmpty {
                ContentUnavailableView(
                    "Nothing to review", systemImage: "checkmark.circle",
                    description: Text("Uncertain captures will wait here instead of being submitted automatically."))
            }
            ForEach(model.reviewItems) { listen in
                ListenRow(listen: listen)
                    .swipeActions(edge: .leading) { Button("Approve") { Task { await model.approve(listen) } }.tint(.green) }
                    .swipeActions {
                        Button("Dismiss", role: .destructive) { Task { await model.dismiss(listen) } };
                        Button("Edit") { model.presentedEditor = listen }.tint(.blue)
                    }
            }
        }
        .navigationTitle("Review")
        .toolbar {
            if !model.reviewItems.isEmpty {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Approve All") { Task { await model.approveAll() } };
                    Menu {
                        Button("Dismiss All", role: .destructive) { Task { await model.dismissAll() } }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

struct ListenRow: View {
    let listen: CanonicalListen
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 30)
            VStack(alignment: .leading) {
                Text(listen.canonicalMetadata.title).font(.headline); Text(listen.canonicalMetadata.artist).foregroundStyle(.secondary);
                if let reason = listen.reviewReason { Text(reason.rawValue.spaced).font(.caption).foregroundStyle(.orange) }
            }
            Spacer();
            VStack(alignment: .trailing) {
                Text(listen.state.rawValue.spaced).font(.caption.weight(.semibold));
                if let date = listen.canonicalMetadata.startedAt { Text(date, style: .time).font(.caption2).foregroundStyle(.secondary) }
            }
        }.accessibilityElement(children: .combine)
    }
    private var icon: String {
        switch listen.state {
        case .submitted: "checkmark.circle.fill";
        case .review: "questionmark.circle.fill";
        case .failed: "exclamationmark.triangle.fill";
        case .privateListen: "eye.slash.fill";
        default: "music.note"
        }
    }
    private var color: Color {
        switch listen.state {
        case .submitted: .green;
        case .review: .orange;
        case .failed: .red;
        default: .pink
        }
    }
}

struct CompanionSettingsView: View {
    let model: CompanionAppModel
    var body: some View {
        Form {
            Section("Apple Music") {
                LabeledContent("Permission", value: String(describing: model.musicAuthorization).capitalized);
                Button("Reconcile Now") { Task { await model.reconcile() } }
            }
            Section("Last.fm") {
                if let username = model.lastFMUsername {
                    LabeledContent("Account", value: username); Button("Disconnect", role: .destructive) { Task { await model.disconnectLastFM() } }
                } else {
                    Button("Connect Last.fm") { Task { await model.connectLastFM() } }.disabled(!model.isConfigured);
                    if !model.isConfigured {
                        Text("Add credentials to ignored Config/Local.xcconfig, then rebuild.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Privacy and sync") {
                Toggle("Global Private Mode", isOn: Binding(get: { model.snapshot.privateMode }, set: { value in Task { await model.setPrivateMode(value) } }));
                LabeledContent("iCloud", value: model.cloudStatus);
                Text("Private Mode blocks cloud-coordinated publishing. An offline device receives the policy when sync resumes.").font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                Button("Prepare Redacted Export") { Task { await model.exportDiagnostics() } };
                if let url = model.diagnosticsURL { ShareLink(item: url) { Label("Share Diagnostics", systemImage: "square.and.arrow.up") } }
            }
            Section("Build") {
                Text("This source-built app uses personal credentials from Config/Local.xcconfig. Never distribute your compiled binary or commit that file.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Settings")
    }
}

struct MetadataEditor: View {
    let model: CompanionAppModel; let listen: CanonicalListen
    @Environment(\.dismiss) private var dismiss
    @State private var title: String; @State private var artist: String; @State private var album: String
    init(model: CompanionAppModel, listen: CanonicalListen) {
        self.model = model; self.listen = listen; _title = State(initialValue: listen.canonicalMetadata.title);
        _artist = State(initialValue: listen.canonicalMetadata.artist); _album = State(initialValue: listen.canonicalMetadata.album ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Submitted metadata") {
                    TextField("Title", text: $title); TextField("Artist", text: $artist); TextField("Album", text: $album)
                };
                Section {
                    Text("The original capture remains in the local audit trail. Timestamp, duration, and source identity cannot be changed.").font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Correct Metadata").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } };
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await model.saveCorrection(id: listen.id, title: title, artist: artist, album: album.isEmpty ? nil : album); dismiss()
                        }
                    }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || artist.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

private func duration(_ value: TimeInterval) -> String { let total = Int(max(0, value)); return String(format: "%d:%02d", total / 60, total % 60) }
private extension String {
    var spaced: String {
        replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).replacingOccurrences(of: "_", with: " ").capitalized
    }
}

#Preview { CompanionRootView(model: CompanionAppModel()) }
