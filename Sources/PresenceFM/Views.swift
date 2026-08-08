import AppKit
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            VStack(spacing: 0) {
                SidebarHeader()
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                List(DashboardSection.allCases, selection: $model.selectedSection) { section in
                    Label(section.rawValue, systemImage: section.symbol)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(model.selectedSection == section ? BrandColors.electricBlue : .primary)
                        .padding(.vertical, 4)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                                .fill(model.selectedSection == section ? BrandColors.electricBlue.opacity(0.16) : Color.clear)
                                .padding(.vertical, 2)
                        )
                        .tag(section)
                        .accessibilityIdentifier("dashboard.section.\(section.id.rawValue)")
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("dashboard.navigation")
                .safeAreaInset(edge: .bottom) {
                    SidebarPrivacyControl()
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 310)
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
        .presencePanelBackground()
        .frame(minWidth: DashboardLayout.minimumWidth, minHeight: DashboardLayout.minimumHeight)
    }
}

struct NowPlayingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.xxxl) {
                if model.demoModeEnabled {
                    HStack(spacing: 14) {
                        Label("Demo playback is active — Discord and Last.fm publishing are paused", systemImage: "testtube.2")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(BrandColors.electricBlue)
                        Spacer()
                        Button("End Demo") { model.setDemoModeEnabled(false) }
                    }
                    .padding(16)
                    .presenceCard(elevated: true)
                    .frame(maxWidth: 960)
                    .accessibilityElement(children: .contain)
                }
                heroSection
                    .frame(maxWidth: 1040)
                VStack(spacing: 0) {
                    ServiceHealthRow(
                        title: model.playbackServiceName,
                        detail: "Playback detection",
                        symbol: "music.note",
                        status: model.musicStatus,
                        statusLabelOverride: nil,
                        recoveryTitle: model.musicStatus == .awaitingPermission ? IntegrationID.appleMusic.recoveryTitle : nil,
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
                .frame(maxWidth: 1040)
            }
            .padding(BrandSpacing.xxl)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Now Playing")
    }

    private var heroSection: some View {
        let currentTrackID = model.snapshot.track?.identity.persistentID ?? "empty"
        let isPlaying = model.snapshot.state == .playing && !reduceMotion
        return ZStack {
            heroBackground
            VStack(alignment: .leading, spacing: BrandSpacing.xl) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: BrandSpacing.xl) {
                        heroArtwork(size: 300, isPlaying: isPlaying)
                        nowPlayingDetails
                            .frame(minWidth: 380, maxWidth: 560, alignment: .leading)
                    }
                    VStack(spacing: BrandSpacing.lg) {
                        heroArtwork(size: 220, isPlaying: isPlaying)
                        nowPlayingDetails
                            .frame(maxWidth: 620, alignment: .leading)
                    }
                }
            }
            .padding(BrandSpacing.xxl)
        }
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: BrandRadius.xxl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BrandRadius.xxl, style: .continuous)
                .strokeBorder(BrandColors.cyan.opacity(0.16), lineWidth: 1)
        }
        .presenceCard(elevated: true)
        .presenceHeroGlow(active: model.snapshot.state == .playing)
        .animation(.easeInOut(duration: 0.28), value: currentTrackID)
    }

    @ViewBuilder
    private var nowPlayingDetails: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Label(playbackLabel, systemImage: model.snapshot.state == .playing ? "dot.radiowaves.left.and.right" : "music.note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .textCase(.uppercase)
            Text(model.snapshot.track?.title ?? "Nothing Playing")
                .font(BrandTypography.heroTitle)
                .lineLimit(2)
            Text(metadataLabel)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let track = model.snapshot.track {
                if track.supportsFiniteProgress {
                    PlaybackProgress(snapshot: model.snapshot, duration: track.duration)
                }
                ScrobbleProgress(state: model.scrobblePresentation)
                if let url = track.appleMusicURL {
                    Link("Open in \(track.platform.rawValue)", destination: url)
                        .presenceButton(prominent: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if model.demoModeEnabled {
                        Text("Starting safe demo playback…")
                    } else {
                        Text("Play something in a supported music app and PresenceFM will pick it up automatically.")
                        Text("Apple Music · Spotify · YouTube Music · TIDAL")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                        Button("Start Demo Playback", systemImage: "play.fill") {
                            model.setDemoModeEnabled(true)
                        }
                        .presenceButton(prominent: true)
                        .help("Try PresenceFM without a music app or service account")
                    }
                }
                .padding(.top, 4)
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
        return model.artworkImage == nil ? "Album artwork unavailable for \(track.title)" : "Album artwork for \(track.title)"
    }

    private func heroArtwork(size: CGFloat, isPlaying: Bool) -> some View {
        ZStack {
            ArtworkView(
                image: model.artworkImage,
                size: size,
                accessibilityDescription: artworkAccessibilityDescription
            )
            .presenceHeroGlow(active: isPlaying)
            .overlay(alignment: .bottomTrailing) {
                if isPlaying {
                    SpinningBrandMark(isSpinning: true)
                        .frame(width: size * 0.28, height: size * 0.28)
                        .padding(size * 0.055)
                        .background(.ultraThinMaterial, in: .circle)
                        .shadow(color: BrandColors.cyan.opacity(0.26), radius: 18, y: 8)
                }
            }
        }
        .id(currentTrackIdentifier)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var currentTrackIdentifier: String {
        model.snapshot.track?.identity.persistentID ?? "empty"
    }

    private var heroBackground: some View {
        ZStack {
            if let image = model.artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 68)
                    .scaleEffect(1.18)
                    .opacity(0.34)
            } else {
                LinearGradient(
                    colors: [BrandColors.cyan.opacity(0.18), BrandColors.electricBlue.opacity(0.12), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            Rectangle().fill(BrandColors.ink.opacity(0.52))
            RadialGradient(
                colors: [BrandColors.cyan.opacity(0.20), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 560
            )
            RadialGradient(
                colors: [BrandColors.electricBlue.opacity(0.18), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 520
            )
        }
        .clipped()
    }

    private var discordRecoveryTitle: String? {
        guard model.preferences.discordEnabled else { return nil }
        return model.discordStatus.isConnected || model.discordStatus == .connecting ? nil : IntegrationID.discord.recoveryTitle
    }

    private var lastFMRecoveryTitle: String? {
        guard model.preferences.lastFMEnabled else { return nil }
        return model.lastFMStatus.isConnected || model.lastFMStatus == .connecting ? nil : IntegrationID.lastFM.recoveryTitle
    }
}

struct ArtworkView: View {
    let data: Data?
    let image: NSImage?
    let size: CGFloat
    var accessibilityDescription: String? = nil

    init(data: Data?, size: CGFloat, accessibilityDescription: String? = nil) {
        self.data = data
        image = nil
        self.size = size
        self.accessibilityDescription = accessibilityDescription
    }

    init(image: NSImage?, size: CGFloat, accessibilityDescription: String? = nil) {
        data = nil
        self.image = image
        self.size = size
        self.accessibilityDescription = accessibilityDescription
    }

    var body: some View {
        Group {
            if let image = image ?? data.flatMap(NSImage.init(data:)) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [BrandColors.ink, BrandColors.night, BrandColors.electricBlue.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    BrandMark()
                        .padding(size * 0.2)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: size * 0.12, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1) }
        .shadow(color: .black.opacity(0.24), radius: size * 0.10, y: size * 0.05)
        .accessibilityLabel(accessibilityDescription ?? (image == nil && data == nil ? "Album artwork unavailable" : "Album artwork"))
    }
}

enum DashboardLayout {
    static let minimumWidth: CGFloat = 640
    static let minimumHeight: CGFloat = 520
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
                case .listening(let progress, _): ProgressView(value: progress).tint(BrandColors.accentRibbon)
                case .ineligible(let reason): Text(reason).font(.caption).foregroundStyle(.secondary)
                default: EmptyView()
                }
            }
            .padding(12)
            .background(BrandColors.electricBlue.opacity(0.08), in: .rect(cornerRadius: BrandRadius.md, style: .continuous))
        }
    }

    private func symbol(for state: ScrobblePresentationState) -> String {
        switch state { case .ineligible: "nosign"; case .listening: "waveform"; case .ready: "checkmark.circle"; case .queued: "tray"; case .submitted: "checkmark.circle.fill" }
    }
}

struct StatusCapsule: View {
    let title: String
    let status: ServiceStatus
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text("\(title): \(status.presentationLabel)")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .presenceCard(capsule: true)
        .scaleEffect(status.isConnected && !reduceMotion ? (pulse ? 1.012 : 1.0) : 1.0)
        .onAppear {
            guard status.isConnected, !reduceMotion else { return }
            pulse = true
        }
    }

    private var statusColor: Color {
        switch status {
        case .connected: BrandColors.success
        case .connecting, .awaitingPermission, .authorizationExpired: BrandColors.warning
        case .failed: BrandColors.error
        case .disabled, .inactive, .offline: BrandColors.neutral
        }
    }
}

struct SidebarHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            BrandMark()
                .frame(width: 30, height: 30)
                .padding(8)
                .background(.ultraThinMaterial, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("PresenceFM")
                    .font(BrandTypography.cardTitle)
                Text(model.isPrivate ? "Private Mode active" : "Control center")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.isPrivate ? "PresenceFM, Private Mode active" : "PresenceFM, Control center")
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
                ZStack {
                    RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                        .fill(BrandColors.accentRibbon.opacity(0.14))
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(BrandColors.electricBlue)
                }
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(BrandTypography.cardTitle)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    StatusCapsule(title: title, status: status)
                    if let override = statusLabelOverride {
                        Text(override)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let detail = status.detailLabel {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(statusLabelOverride ?? status.presentationLabel)")
            if let recoveryTitle {
                Button(recoveryTitle, action: recoveryAction)
                    .presenceButton(prominent: true)
                    .accessibilityHint("Attempts to recover the \(title) connection")
                    .accessibilityIdentifier("recovery.\(recoveryIdentifier)")
            }
        }
        .padding(16)
        .presenceCard(elevated: true)
        .accessibilityElement(children: .contain)
    }

    private var recoveryIdentifier: String {
        title.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
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
        VStack(alignment: .leading, spacing: 10) {
            Label(model.isPrivate ? "Private Mode is on" : "Go Private", systemImage: model.isPrivate ? "eye.slash.fill" : "eye.slash")
                .font(.headline)
            Text(model.isPrivate ? privateDetail : "Pause Discord sharing and Last.fm updates at any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PrivacyControls()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presenceCard(elevated: true)
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
                ArtworkView(image: model.artworkImage, size: 68)
                VStack(alignment: .leading) {
                    Text(model.snapshot.track?.title ?? "Nothing Playing").font(.headline).lineLimit(1)
                    Text(model.snapshot.track?.artist ?? "Choose a connected music app").foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if let track = model.snapshot.track {
                if track.supportsFiniteProgress {
                    PlaybackProgress(snapshot: model.snapshot, duration: track.duration)
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
            Text(statusLabelOverride ?? status.presentationLabel).foregroundStyle(.secondary)
        }
            .font(.caption)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(name), \(statusLabelOverride ?? status.presentationLabel)")
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
    @State private var correction: QueueCorrection?
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
                            Text(record.title).font(.headline).lineLimit(1)
                            Text(record.artist).foregroundStyle(.secondary).lineLimit(1)
                            if let error = record.lastError, error != commonError {
                                Text(error).font(.caption).foregroundStyle(BrandColors.error).lineLimit(2)
                            }
                        }
                        Spacer()
                        Text(record.stateRaw.queueDisplayName).foregroundStyle(.secondary)
                        Menu("Actions", systemImage: "ellipsis.circle") {
                            if record.state == .permanentlyFailed {
                                Button("Edit and Retry…") { requestCorrection(of: record) }
                                Button("Retry Without Changes") { model.retryScrobble(id: record.id) }
                            }
                            Button("Remove…", role: .destructive) { requestRemoval(of: record) }
                        }
                        .menuIndicator(.hidden)
                        .accessibilityLabel("Actions for \(record.title)")
                    }
                    .contextMenu {
                        if record.state == .permanentlyFailed {
                            Button("Edit and Retry…") { requestCorrection(of: record) }
                            Button("Retry Without Changes") { model.retryScrobble(id: record.id) }
                        }
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
        .sheet(item: $correction) { draft in
            QueueCorrectionView(draft: draft) { updated in
                if model.correctScrobble(
                    id: updated.id,
                    title: updated.title,
                    artist: updated.artist,
                    album: updated.album
                ) {
                    correction = nil
                }
            }
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

    private func requestCorrection(of record: ScrobbleRecord) {
        correction = QueueCorrection(
            id: record.id,
            title: record.title,
            artist: record.artist,
            album: record.album ?? ""
        )
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
                if model.musicStatus == .awaitingPermission { Button(IntegrationID.appleMusic.recoveryTitle ?? "Open Settings") { model.openAutomationSettings() } }
                if model.preferences.discordEnabled, !model.discordStatus.isConnected, model.discordStatus != .connecting { Button(IntegrationID.discord.recoveryTitle ?? "Reconnect") { model.refreshDiscord() } }
                if model.lastFMStatus == .authorizationExpired { Button(IntegrationID.lastFM.recoveryTitle ?? "Reconnect") { model.selectedSection = .settings } }
            }
            Section("Support Report") {
                Button("Copy Redacted Support Report", systemImage: "doc.on.doc") { model.copyDiagnosticReport() }
                Text(model.diagnosticCopyStatus.isEmpty ? "Includes app, macOS, connection status, and the latest redacted diagnostic messages. It excludes credentials and listening metadata." : model.diagnosticCopyStatus)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Release Verification") {
                HStack {
                    Button("Copy Snapshot", systemImage: "doc.on.doc", action: model.copyVerificationReport)
                    Button("Save Snapshot…", systemImage: "square.and.arrow.down", action: model.saveVerificationReport)
                }
                Text(model.verificationExportStatus.isEmpty ? "Exports version, environment, provider health, poll timing, and bounded local-data counts. Track metadata, usernames, credentials, and paths are excluded." : model.verificationExportStatus)
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

extension TimeInterval {
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
