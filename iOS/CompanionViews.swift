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
                NavigationStack { LastFMHomeView(model: model) }
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
                VStack(spacing: CompanionSpacing.lg) {
                    header
                    if model.lastFMUsername != nil {
                        CompanionReadinessView(model: model)
                    } else if model.hasLastFMCredentials {
                        authorizationActions
                    } else {
                        credentialForm
                    }
                    footnote
                }
                .companionReadableColumn()
                .padding(.horizontal, CompanionSpacing.lg)
                .padding(.vertical, CompanionSpacing.xl)
            }
            .background(CompanionBrand.canvas.ignoresSafeArea())
        }
    }

    private var header: some View {
        VStack(spacing: CompanionSpacing.md) {
            CompanionBrandMark()
                .frame(width: 96, height: 96)
                .padding(CompanionSpacing.md)
                .background(CompanionBrand.electricBlue.opacity(0.10), in: Circle())
            VStack(spacing: CompanionSpacing.xs) {
                Text("Connect Last.fm")
                    .font(.largeTitle.bold())
                Text(
                    model.hasLastFMCredentials
                        ? "Your API credentials are saved. Finish by authorizing your Last.fm account."
                        : "Add your own Last.fm API application once, then authorize your account."
                )
                .font(.callout)
                .foregroundStyle(CompanionBrand.secondaryText)
                .multilineTextAlignment(.center)
            }
        }
        .padding(.bottom, CompanionSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var authorizationActions: some View {
        VStack(spacing: CompanionSpacing.sm) {
            Button("Authorize with Last.fm") { Task { await model.connectLastFM() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            if model.hasPendingLastFMAuthorization {
                Button("I've Authorized — Finish Connection") { Task { await model.finishLastFMConnection() } }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Text("If Last.fm leaves the browser open after approval, return here and tap Finish Connection.")
                    .font(.caption)
                    .foregroundStyle(CompanionBrand.secondaryText)
                    .multilineTextAlignment(.center)
            }
            Button("Use Different API Credentials") { Task { await model.clearLastFMCredentials() } }
                .font(.footnote.weight(.medium))
                .foregroundStyle(CompanionBrand.secondaryText)
                .padding(.top, CompanionSpacing.xs)
        }
        .companionCard(padding: CompanionSpacing.lg)
    }

    private var credentialForm: some View {
        VStack(alignment: .leading, spacing: CompanionSpacing.md) {
            Text("API credentials")
                .font(.subheadline.weight(.semibold))
            VStack(spacing: CompanionSpacing.sm) {
                TextField("API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                SecureField("Shared secret", text: $sharedSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }
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
            Link(destination: URL(string: "https://www.last.fm/api/account/create")!) {
                Label("Create a Last.fm API application", systemImage: "arrow.up.right.square")
                    .font(.footnote.weight(.medium))
            }
        }
        .companionCard(padding: CompanionSpacing.lg)
    }

    private var footnote: some View {
        Label {
            Text("Set the callback URL to https://presence-fm.vercel.app/lastfm-callback.html. Credentials stay in this iPhone's Keychain.")
        } icon: {
            Image(systemName: "lock.fill")
        }
        .font(.caption)
        .foregroundStyle(CompanionBrand.secondaryText)
        .padding(.horizontal, CompanionSpacing.xs)
    }
}

struct LastFMHomeView: View {
    let model: CompanionAppModel
    var body: some View {
        List {
            Section {
                CompanionCaptureStatusCard(model: model)
                    .listRowInsets(EdgeInsets(top: CompanionSpacing.xs, leading: 0, bottom: CompanionSpacing.md, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if model.musicAuthorization != .authorized {
                Section {
                    Button("Enable Apple Music scrobbling", systemImage: "music.note") { Task { await model.requestMusicAccess() } }
                } footer: {
                    Text("Music access lets PresenceFM submit newly played songs to Last.fm.")
                }
            }
            Section {
                if model.isImportingAppleMusicHistory {
                    HStack(spacing: CompanionSpacing.sm) {
                        ProgressView()
                        Text("Reading Apple Music history…")
                            .foregroundStyle(CompanionBrand.secondaryText)
                    }
                } else if !model.historicalImportItems.isEmpty {
                    NavigationLink {
                        HistoricalScrobbleSelectionView(model: model)
                    } label: {
                        LabeledContent {
                            Text("\(model.historicalImportItems.count)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(CompanionBrand.electricBlue)
                        } label: {
                            Label("Choose past plays to scrobble", systemImage: "checklist")
                        }
                    }
                }
                Button("Scan Apple Music History Again", systemImage: "arrow.clockwise") {
                    Task { await model.importAvailableAppleMusicHistory() }
                }
                .disabled(model.isImportingAppleMusicHistory)
                if let count = model.lastAppleMusicImportCount {
                    Text(count == 0 ? "No new history was found." : "Found \(count) new candidate\(count == 1 ? "" : "s").")
                        .font(.caption)
                        .foregroundStyle(CompanionBrand.secondaryText)
                }
            } header: {
                CompanionSectionHeader(title: "Past plays")
            } footer: {
                Text("Apple Music exposes a limited recently-played list, not a complete play-by-play archive. Repeated plays may appear only once.")
            }
            Section {
                if model.isLoadingLastFMHistory, model.lastFMTracks.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                } else if model.lastFMTracks.isEmpty {
                    ContentUnavailableView("No scrobbles yet", systemImage: "waveform", description: Text("Your Last.fm history will appear here."))
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(model.lastFMTracks) { track in LastFMTrackRow(track: track) }
                }
            } header: {
                CompanionSectionHeader(title: model.lastFMUsername ?? "Last.fm") {
                    if model.isLoadingLastFMHistory { ProgressView().controlSize(.small) }
                }
            } footer: {
                if let issue = model.captureIssue {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                NavigationLink {
                    CompanionCaptureActivityView(model: model)
                } label: {
                    Label("Why plays did or didn’t scrobble", systemImage: "list.bullet.clipboard")
                }
            } header: {
                CompanionSectionHeader(title: "Capture details")
            }
        }
        .companionCanvas()
        .listStyle(.insetGrouped)
        .navigationTitle("Scrobbles")
        .refreshable { await model.refreshLastFMHistory() }
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
}

struct CompanionReadinessView: View {
    let model: CompanionAppModel

    var body: some View {
        VStack(spacing: CompanionSpacing.md) {
            HStack {
                CompanionStatusPill(title: "Last.fm connected", symbol: "checkmark.circle.fill", tint: .green)
                Spacer()
            }
            CompanionCaptureStatusCard(model: model)
            VStack(spacing: CompanionSpacing.sm) {
                if model.musicAuthorization != .authorized {
                    Button("Allow Apple Music Access") { Task { await model.requestMusicAccess() } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
                Button(model.isReadyForCapture ? "Find Past Plays and Continue" : "Continue with Limited Capture") {
                    Task {
                        if model.isReadyForCapture { await model.importAvailableAppleMusicHistory() }
                        model.completeReadiness()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                if model.isReadyForCapture {
                    Button("Continue Without Importing") { model.completeReadiness() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
            }
            Text("iOS may suspend background observation. PresenceFM checks recent plays when the system gives it runtime; keeping the app open provides the strongest evidence.")
                .font(.caption)
                .foregroundStyle(CompanionBrand.secondaryText)
                .multilineTextAlignment(.center)
        }
        .companionCard(padding: CompanionSpacing.lg)
    }
}

struct HistoricalScrobbleSelectionView: View {
    let model: CompanionAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs = Set<String>()
    @State private var isSubmitting = false
    @State private var searchText = ""
    @State private var period: HistoricalImportPeriod = .all

    var body: some View {
        List {
            Section {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No matching plays",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search or a wider date range.")
                    )
                    .listRowSeparator(.hidden)
                }
                ForEach(filteredItems) { listen in
                    Button {
                        toggle(listen.id)
                    } label: {
                        HStack(spacing: CompanionSpacing.md) {
                            Image(systemName: selectedIDs.contains(listen.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.contains(listen.id) ? CompanionBrand.electricBlue : Color.secondary)
                                .font(.title3)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(listen.canonicalMetadata.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(listen.canonicalMetadata.artist)
                                    .font(.subheadline)
                                    .foregroundStyle(CompanionBrand.secondaryText)
                                    .lineLimit(1)
                                if let album = listen.canonicalMetadata.album, !album.isEmpty {
                                    Text(album)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: CompanionSpacing.sm)
                            if let date = listen.canonicalMetadata.startedAt {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(date, format: .dateTime.month(.abbreviated).day())
                                        .font(.caption.weight(.medium).monospacedDigit())
                                    Text(date, format: .dateTime.hour().minute())
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                                .foregroundStyle(CompanionBrand.secondaryText)
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selectionAccessibilityLabel(for: listen))
                    .accessibilityAddTraits(selectedIDs.contains(listen.id) ? .isSelected : [])
                }
            } header: {
                CompanionSectionHeader(title: "\(filteredItems.count) available") {
                    if !visibleSelectedIDs.isEmpty {
                        Text("\(visibleSelectedIDs.count) selected")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(CompanionBrand.electricBlue)
                            .textCase(nil)
                    }
                }
            } footer: {
                Text("Only selected songs are sent to Last.fm. Submitting a historical scrobble cannot be undone from PresenceFM.")
            }
        }
        .listStyle(.insetGrouped)
        .companionCanvas()
        .navigationTitle("Choose Past Plays")
        .searchable(text: $searchText, prompt: "Song or artist")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu(period.title) {
                    Picker("Date range", selection: $period) {
                        ForEach(HistoricalImportPeriod.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(allVisibleSelected ? "Deselect All" : "Select All") {
                    let visibleIDs = Set(filteredItems.map(\.id))
                    if allVisibleSelected {
                        selectedIDs.subtract(visibleIDs)
                    } else {
                        selectedIDs.formUnion(visibleIDs)
                    }
                }
                .disabled(filteredItems.isEmpty || isSubmitting)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: CompanionSpacing.xs) {
                Button {
                    isSubmitting = true
                    let submittedIDs = visibleSelectedIDs
                    Task {
                        await model.approveHistoricalImports(ids: submittedIDs)
                        isSubmitting = false
                        if model.historicalImportItems.isEmpty { dismiss() }
                        selectedIDs.formIntersection(Set(model.historicalImportItems.map(\.id)))
                    }
                } label: {
                    if isSubmitting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(visibleSelectedIDs.isEmpty ? "Select Plays to Scrobble" : "Scrobble \(visibleSelectedIDs.count) Selected")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(visibleSelectedIDs.isEmpty || isSubmitting)
                Text("Sent with their original play times.")
                    .font(.caption2)
                    .foregroundStyle(CompanionBrand.secondaryText)
            }
            .companionReadableColumn()
            .padding(.horizontal, CompanionSpacing.lg)
            .padding(.vertical, CompanionSpacing.sm)
            .background(.bar)
        }
    }

    private var filteredItems: [CanonicalListen] {
        let cutoff = period.days.map { Calendar.current.date(byAdding: .day, value: -$0, to: .now) ?? .distantPast }
        return model.historicalImportItems.filter { listen in
            let matchesDate = cutoff.map { (listen.canonicalMetadata.startedAt ?? .distantPast) >= $0 } ?? true
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).presenceNormalized
            let matchesSearch = query.isEmpty
                || listen.canonicalMetadata.title.presenceNormalized.contains(query)
                || listen.canonicalMetadata.artist.presenceNormalized.contains(query)
            return matchesDate && matchesSearch
        }
    }

    private var allVisibleSelected: Bool {
        !filteredItems.isEmpty && filteredItems.allSatisfy { selectedIDs.contains($0.id) }
    }

    private var visibleSelectedIDs: Set<String> {
        selectedIDs.intersection(Set(filteredItems.map(\.id)))
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func selectionAccessibilityLabel(for listen: CanonicalListen) -> String {
        "\(selectedIDs.contains(listen.id) ? "Selected" : "Not selected"), \(listen.canonicalMetadata.title) by \(listen.canonicalMetadata.artist)"
    }
}

private enum HistoricalImportPeriod: String, CaseIterable, Identifiable {
    case sevenDays, thirtyDays, all

    var id: Self { self }
    var title: String {
        switch self {
        case .sevenDays: "7 Days"
        case .thirtyDays: "30 Days"
        case .all: "All Available"
        }
    }
    var days: Int? {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        case .all: nil
        }
    }
}

struct CompanionCaptureStatusCard: View {
    let model: CompanionAppModel

    var body: some View {
        let presentation = model.captureStatus
        VStack(alignment: .leading, spacing: CompanionSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: CompanionSpacing.sm) {
                CompanionStatusPill(
                    title: presentation.status.title,
                    symbol: presentation.status.symbol,
                    tint: presentation.status.tint
                )
                Spacer()
                if let timestamp = presentation.timestamp {
                    Text(timestamp, style: .relative)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(CompanionBrand.secondaryText)
                }
            }
            if let evidence = model.nowPlaying {
                VStack(alignment: .leading, spacing: 2) {
                    Text(evidence.originalMetadata.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(evidence.originalMetadata.artist)
                        .font(.subheadline)
                        .foregroundStyle(CompanionBrand.secondaryText)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
            if let progress = presentation.progress {
                ProgressView(value: progress)
                    .tint(CompanionBrand.signalCyan)
                    .accessibilityLabel("Scrobble eligibility")
                    .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.headline)
                    .font(.subheadline.weight(.semibold))
                Text(presentation.explanation)
                    .font(.caption)
                    .foregroundStyle(CompanionBrand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action = presentation.recoveryAction {
                Button(action.buttonTitle) { Task { await model.performCaptureRecovery(action) } }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
        }
        .companionCard()
        .accessibilityElement(children: .contain)
    }
}

struct CompanionCaptureActivityView: View {
    let model: CompanionAppModel

    var body: some View {
        List {
            if model.recentCaptureActivity.isEmpty {
                ContentUnavailableView(
                    "No captured plays yet",
                    systemImage: "waveform.badge.magnifyingglass",
                    description: Text("PresenceFM will explain captured, queued, private, and uncertain plays here.")
                )
            }
            ForEach(Array(model.recentCaptureActivity.enumerated()), id: \.offset) { _, activity in
                HStack(alignment: .top, spacing: CompanionSpacing.md) {
                    Image(systemName: activity.status.symbol)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(activity.status.tint)
                        .frame(width: 30, height: 30)
                        .background(activity.status.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: CompanionRadius.sm, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(activity.headline)
                            .font(.subheadline.weight(.semibold))
                        Text(activity.explanation)
                            .font(.caption)
                            .foregroundStyle(CompanionBrand.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: CompanionSpacing.xs)
                    if let timestamp = activity.timestamp {
                        Text(timestamp, style: .relative)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            if !model.reviewItems.isEmpty {
                Section("Needs review") {
                    ForEach(model.reviewItems) { listen in
                        ListenRow(listen: listen)
                            .swipeActions(edge: .leading) {
                                Button("Approve") { Task { await model.approve(listen) } }.tint(.green)
                            }
                            .swipeActions {
                                Button("Dismiss", role: .destructive) { Task { await model.dismiss(listen) } }
                                Button("Edit") { model.presentedEditor = listen }.tint(.blue)
                            }
                    }
                }
            }
        }
        .companionCanvas()
        .navigationTitle("Capture Details")
    }
}

private extension CaptureStatusPresentation.Status {
    var title: String {
        switch self {
        case .detecting: "Listening"
        case .progressing: "In progress"
        case .queued: "Queued"
        case .submitted: "Scrobbled"
        case .excluded: "Not eligible"
        case .privateMode: "Private Mode"
        case .needsAttention: "Needs attention"
        }
    }

    var symbol: String {
        switch self {
        case .detecting: "waveform.badge.magnifyingglass"
        case .progressing: "waveform"
        case .queued: "tray.full"
        case .submitted: "checkmark.circle.fill"
        case .excluded: "nosign"
        case .privateMode: "eye.slash.fill"
        case .needsAttention: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .submitted: .green
        case .detecting, .progressing: CompanionBrand.electricBlue
        case .queued, .privateMode: .orange
        case .excluded: .secondary
        case .needsAttention: .red
        }
    }
}

private extension CaptureStatusPresentation.RecoveryAction {
    var buttonTitle: String {
        switch self {
        case .grantPlaybackPermission: "Grant Permission"
        case .reconnectLastFM: "Reconnect Last.fm"
        case .retryQueue: "Retry Queue"
        case .disablePrivateMode: "End Private Mode"
        case .openSettings: "Check Again"
        }
    }
}

/// A list section header in title case with an optional trailing accessory.
struct CompanionSectionHeader<Accessory: View>: View {
    private let title: String
    private let accessory: Accessory

    init(title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
            Spacer()
            accessory
        }
    }
}

extension CompanionSectionHeader where Accessory == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// A compact tinted capsule used for scrobble and capture states.
struct CompanionStatusPill: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

struct LastFMTrackRow: View {
    let track: CompanionLastFMTrack

    var body: some View {
        HStack(spacing: CompanionSpacing.md) {
            AsyncImage(url: track.artworkURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    CompanionBrand.discGradient.opacity(0.16)
                        .overlay { CompanionBrandMark().padding(10) }
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: CompanionRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CompanionRadius.sm, style: .continuous)
                    .strokeBorder(CompanionBrand.hairline, lineWidth: 1)
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(CompanionBrand.secondaryText)
                    .lineLimit(1)
                if let album = track.album, !album.isEmpty {
                    Text(album)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: CompanionSpacing.xs)
            if track.isNowPlaying {
                CompanionStatusPill(title: "Now", symbol: "waveform", tint: CompanionBrand.electricBlue)
            } else if let date = track.playedAt {
                Text(date, style: .relative)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct CaptureHealthCard: View {
    let model: CompanionAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: CompanionSpacing.sm) {
            Label("Capture health", systemImage: "checkmark.shield")
                .font(.subheadline.weight(.semibold))
            Divider()
            LabeledContent("Last.fm", value: model.lastFMUsername ?? "Not connected")
            LabeledContent("iCloud", value: model.cloudStatus)
            LabeledContent("Queued", value: String(model.history.filter { $0.state == .queued }.count))
            if model.snapshot.privateMode {
                CompanionStatusPill(title: "Private Mode is active", symbol: "eye.slash.fill", tint: .orange)
            }
        }
        .font(.subheadline)
        .companionCard()
    }
}

struct HistoryView: View {
    let model: CompanionAppModel

    var body: some View {
        List {
            if model.history.isEmpty {
                ContentUnavailableView(
                    "No listening history", systemImage: "clock", description: Text("Observed and reviewed Apple Music listens appear here.")
                )
                .listRowSeparator(.hidden)
            }
            ForEach(model.history) { listen in
                ListenRow(listen: listen)
                    .swipeActions {
                        if listen.state == .failed || listen.state == .queued {
                            Button("Retry", systemImage: "arrow.clockwise") { Task { await model.approve(listen) } }
                                .tint(CompanionBrand.electricBlue)
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .companionCanvas()
        .navigationTitle("Captured Plays")
    }
}

struct ReviewView: View {
    let model: CompanionAppModel

    var body: some View {
        List {
            if model.reviewItems.isEmpty {
                ContentUnavailableView(
                    "Nothing to review", systemImage: "checkmark.circle",
                    description: Text("Uncertain captures will wait here instead of being submitted automatically.")
                )
                .listRowSeparator(.hidden)
            }
            ForEach(model.reviewItems) { listen in
                ListenRow(listen: listen)
                    .swipeActions(edge: .leading) {
                        Button("Approve", systemImage: "checkmark") { Task { await model.approve(listen) } }
                            .tint(.green)
                    }
                    .swipeActions {
                        Button("Dismiss", systemImage: "xmark", role: .destructive) { Task { await model.dismiss(listen) } }
                        Button("Edit", systemImage: "pencil") { model.presentedEditor = listen }
                            .tint(CompanionBrand.electricBlue)
                    }
            }
        }
        .listStyle(.insetGrouped)
        .companionCanvas()
        .navigationTitle("Review")
        .toolbar {
            if !model.reviewItems.isEmpty {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Approve All") { Task { await model.approveAll() } }
                    Menu {
                        Button("Dismiss All", systemImage: "trash", role: .destructive) { Task { await model.dismissAll() } }
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
        HStack(spacing: CompanionSpacing.md) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: CompanionRadius.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(listen.canonicalMetadata.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(listen.canonicalMetadata.artist)
                    .font(.subheadline)
                    .foregroundStyle(CompanionBrand.secondaryText)
                    .lineLimit(1)
                if let reason = listen.reviewReason {
                    Text(reason.rawValue.spaced)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: CompanionSpacing.xs)
            VStack(alignment: .trailing, spacing: 4) {
                Text(listen.state.rawValue.spaced)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.14), in: Capsule())
                if let date = listen.canonicalMetadata.startedAt {
                    Text(date, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch listen.state {
        case .submitted: "checkmark.circle.fill"
        case .review: "questionmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .privateListen: "eye.slash.fill"
        default: "music.note"
        }
    }

    private var color: Color {
        switch listen.state {
        case .submitted: .green
        case .review: .orange
        case .failed: .red
        default: CompanionBrand.electricBlue
        }
    }
}

struct CompanionSettingsView: View {
    let model: CompanionAppModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Permission", value: String(describing: model.musicAuthorization).capitalized)
                Button("Reconcile Now", systemImage: "arrow.triangle.2.circlepath") { Task { await model.reconcile() } }
            } header: {
                CompanionSectionHeader(title: "Apple Music")
            } footer: {
                Text("Reconciling re-checks recent plays and resubmits anything still queued.")
            }
            Section {
                if let username = model.lastFMUsername {
                    LabeledContent("Account", value: username)
                    Button("Disconnect", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                        Task { await model.disconnectLastFM() }
                    }
                } else {
                    Button("Connect Last.fm", systemImage: "link") { Task { await model.connectLastFM() } }
                }
                Button("Replace API Credentials", systemImage: "key", role: .destructive) {
                    Task { await model.clearLastFMCredentials() }
                }
            } header: {
                CompanionSectionHeader(title: "Last.fm")
            } footer: {
                Text("Credentials are stored in this device's Keychain and are never synced by PresenceFM.")
            }
            Section {
                Toggle(
                    "Global Private Mode",
                    isOn: Binding(get: { model.snapshot.privateMode }, set: { value in Task { await model.setPrivateMode(value) } })
                )
                LabeledContent("iCloud", value: model.cloudStatus)
            } header: {
                CompanionSectionHeader(title: "Privacy and sync")
            } footer: {
                Text("Private Mode blocks cloud-coordinated publishing. An offline device receives the policy when sync resumes.")
            }
            Section {
                Button("Prepare Redacted Export", systemImage: "doc.badge.gearshape") { Task { await model.exportDiagnostics() } }
                if let url = model.diagnosticsURL {
                    ShareLink(item: url) { Label("Share Diagnostics", systemImage: "square.and.arrow.up") }
                }
            } header: {
                CompanionSectionHeader(title: "Diagnostics")
            } footer: {
                Text("The default free-account build runs locally without CloudKit coordination.")
            }
        }
        .companionCanvas()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MetadataEditor: View {
    let model: CompanionAppModel
    let listen: CanonicalListen
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var artist: String
    @State private var album: String

    init(model: CompanionAppModel, listen: CanonicalListen) {
        self.model = model
        self.listen = listen
        _title = State(initialValue: listen.canonicalMetadata.title)
        _artist = State(initialValue: listen.canonicalMetadata.artist)
        _album = State(initialValue: listen.canonicalMetadata.album ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Artist", text: $artist)
                    TextField("Album", text: $album)
                } header: {
                    CompanionSectionHeader(title: "Submitted metadata")
                } footer: {
                    Text("The original capture remains in the local audit trail. Timestamp, duration, and source identity cannot be changed.")
                }
            }
            .companionCanvas()
            .navigationTitle("Correct Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await model.saveCorrection(id: listen.id, title: title, artist: artist, album: album.isEmpty ? nil : album)
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || artist.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

private extension String {
    var spaced: String {
        replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).replacingOccurrences(of: "_", with: " ").capitalized
    }
}

#Preview { CompanionRootView(model: CompanionAppModel()) }
