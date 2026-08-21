import MusicKit
import PresenceFMCore
import SwiftUI

struct CompanionRootView: View {
    let model: CompanionAppModel
    var body: some View {
        Group {
            if model.needsOnboarding {
                LastFMOnboardingView(model: model)
            } else {
                TabView {
                    NavigationStack { NowPlayingView(model: model) }.tabItem { Label("Now Playing", systemImage: "play.circle.fill") }
                    NavigationStack { HistoryView(model: model) }.tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                    NavigationStack { ReviewView(model: model) }.tabItem { Label("Review", systemImage: "tray.full.fill") }.badge(model.reviewItems.count)
                }
            }
        }
        .tint(CompanionBrand.electricBlue)
        .background(CompanionBrand.canvas.ignoresSafeArea())
        .alert("PresenceFM", isPresented: Binding(get: { model.statusMessage != nil }, set: { if !$0 { model.statusMessage = nil } })) {
            Button("OK") { model.statusMessage = nil }
        } message: {
            Text(model.statusMessage ?? "")
        }
        .sheet(item: Binding(get: { model.presentedEditor }, set: { model.presentedEditor = $0 })) { MetadataEditor(model: model, listen: $0) }
    }
}

struct LastFMOnboardingView: View {
    let model: CompanionAppModel
    @State private var apiKey = ""
    @State private var sharedSecret = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    CompanionBrandMark()
                        .frame(width: 112, height: 112)
                    VStack(spacing: 8) {
                        Text("Connect Last.fm").font(.largeTitle.bold())
                        Text(
                            model.hasLastFMCredentials
                                ? "Your API credentials are saved. Finish by authorizing your Last.fm account."
                                : "Add your own Last.fm API application once, then authorize your account."
                        )
                        .foregroundStyle(CompanionBrand.secondaryText)
                        .multilineTextAlignment(.center)
                    }
                    if model.hasLastFMCredentials {
                        Button("Authorize with Last.fm") { Task { await model.connectLastFM() } }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        if model.hasPendingLastFMAuthorization {
                            Button("I've Authorized — Finish Connection") { Task { await model.finishLastFMConnection() } }
                                .buttonStyle(.bordered)
                            Text("If Last.fm leaves the browser open after approval, return here and tap Finish Connection.")
                                .font(.caption)
                                .foregroundStyle(CompanionBrand.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        Button("Use Different API Credentials") { Task { await model.clearLastFMCredentials() } }
                            .foregroundStyle(CompanionBrand.secondaryText)
                    } else {
                        VStack(spacing: 12) {
                            TextField("API key", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            SecureField("Shared secret", text: $sharedSecret)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button {
                                isSaving = true
                                Task {
                                    if await model.saveLastFMCredentials(apiKey: apiKey, sharedSecret: sharedSecret) {
                                        await model.connectLastFM()
                                    }
                                    isSaving = false
                                }
                            } label: {
                                if isSaving { ProgressView().frame(maxWidth: .infinity) } else { Text("Save and Authorize").frame(maxWidth: .infinity) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(
                                isSaving || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || sharedSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                    Link("Create a Last.fm API application", destination: URL(string: "https://www.last.fm/api/account/create")!)
                    Text("Set its callback URL to https://presence-fm.vercel.app/lastfm-callback.html. Credentials stay in this iPhone's Keychain.")
                        .font(.caption)
                        .foregroundStyle(CompanionBrand.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .background(CompanionBrand.canvas.ignoresSafeArea())
        }
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
                    CompanionBrandMark().frame(width: 76, height: 76)
                    Text(evidence.originalMetadata.title).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(evidence.originalMetadata.artist).foregroundStyle(.secondary)
                    ProgressView(value: progress(evidence)).tint(CompanionBrand.electricBlue)
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
        }.padding().background(CompanionBrand.surface, in: RoundedRectangle(cornerRadius: 18))
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
                    if listen.state == .failed || listen.state == .queued {
                        Button("Retry") { Task { await model.approve(listen) } }.tint(CompanionBrand.electricBlue)
                    }
                }
            }
        }
        .companionCanvas()
        .navigationTitle("History")
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
        .companionCanvas()
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
        default: CompanionBrand.electricBlue
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
                    Button("Connect Last.fm") { Task { await model.connectLastFM() } }
                }
                Button("Replace API Credentials", role: .destructive) { Task { await model.clearLastFMCredentials() } }
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
                Text("Last.fm credentials are stored in this device's Keychain. The default free-account build runs locally without CloudKit coordination.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .companionCanvas()
        .navigationTitle("Settings")
        .toolbar(.hidden, for: .tabBar)
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
