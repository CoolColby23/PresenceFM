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
                List(selection: $model.selectedSection) {
                    Section("Listen") {
                        ForEach(visibleSections([.nowPlaying, .history])) { section in
                            SidebarNavigationRow(section: section, selected: model.selectedSection == section)
                                .tag(section)
                                .contextMenu { sidebarContextMenu(for: section) }
                        }
                    }
                    Section("Manage") {
                        ForEach(visibleSections([.queue, .diagnostics, .settings])) { section in
                            SidebarNavigationRow(section: section, selected: model.selectedSection == section)
                                .tag(section)
                                .contextMenu { sidebarContextMenu(for: section) }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("dashboard.navigation")
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 10) {
                        sidebarCustomization
                        SidebarPrivacyControl()
                    }
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
        .sheet(isPresented: $model.commandPalettePresented) {
            CommandPaletteView().environment(model)
        }
        .safeAreaInset(edge: .top) {
            if let issue = model.persistenceIssue {
                PersistenceRecoveryBanner(message: issue)
            }
        }
        .presencePanelBackground()
        .frame(minWidth: DashboardLayout.minimumWidth, minHeight: DashboardLayout.minimumHeight)
    }

    private func visibleSections(_ sections: [DashboardSection]) -> [DashboardSection] {
        sections.filter(model.preferences.isDashboardSectionVisible)
    }

    @ViewBuilder
    private func sidebarContextMenu(for section: DashboardSection) -> some View {
        if section.canBeHidden {
            Button("Hide from Sidebar", systemImage: "eye.slash") {
                model.preferences.toggleDashboardSection(section)
                if model.selectedSection == section { model.navigate(to: .nowPlaying) }
            }
        }
    }

    private var sidebarCustomization: some View {
        HStack {
            Button("Quick Open", systemImage: "command") {
                model.commandPalettePresented = true
            }
            .buttonStyle(.plain)
            .help("Open commands (Command-K)")
            Spacer()
            Menu("Customize", systemImage: "slider.horizontal.3") {
                ForEach(DashboardSection.allCases.filter(\.canBeHidden)) { section in
                    Button {
                        model.preferences.toggleDashboardSection(section)
                        if model.selectedSection == section,
                           !model.preferences.isDashboardSectionVisible(section) {
                            model.navigate(to: .nowPlaying)
                        }
                    } label: {
                        Label(
                            section.title,
                            systemImage: model.preferences.isDashboardSectionVisible(section)
                                ? "checkmark" : section.symbol
                        )
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

private struct SidebarNavigationRow: View {
    let section: DashboardSection
    let selected: Bool
    @Environment(\.appTheme) private var theme

    var body: some View {
        Label(section.title, systemImage: section.symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(selected ? theme.onPrimaryColor : .primary)
            .padding(.vertical, 4)
            .listRowBackground(
                RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                    .fill(selected ? theme.primaryColor.opacity(0.16) : Color.clear)
                    .padding(.vertical, 2)
            )
            .accessibilityIdentifier("dashboard.section.\(section.id.rawValue)")
    }
}

struct NowPlayingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.xxxl) {
                if model.demoModeEnabled {
                    HStack(spacing: 14) {
                        Label("Demo playback is active — Discord and Last.fm publishing are paused", systemImage: "testtube.2")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(theme.primaryColor)
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
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("At a glance").font(BrandTypography.sectionTitle)
                        Text("See where playback and artwork came from, plus what PresenceFM shared.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    NowPlayingOverviewView()
                }
                .frame(maxWidth: 1040)
            }
            .padding(BrandSpacing.xxl)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Now Playing")
    }

    @ViewBuilder
    private var heroSection: some View {
        if model.snapshot.track == nil {
            emptyHeroSection
        } else {
            populatedHeroSection
        }
    }

    private var populatedHeroSection: some View {
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
                .strokeBorder(theme.secondaryColor.opacity(0.16), lineWidth: 1)
        }
        .presenceCard(elevated: true)
        .presenceHeroGlow(active: model.snapshot.state == .playing)
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: currentTrackID)
    }

    private var emptyHeroSection: some View {
        ZStack {
            heroBackground
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    BrandMark()
                        .frame(width: 92, height: 92)
                        .padding(24)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 26))
                    nowPlayingDetails
                        .frame(maxWidth: 620, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 18) {
                    BrandMark().frame(width: 72, height: 72)
                    nowPlayingDetails
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(.rect(cornerRadius: BrandRadius.xxl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BrandRadius.xxl, style: .continuous)
                .strokeBorder(theme.secondaryColor.opacity(0.16), lineWidth: 1)
        }
        .presenceCard(elevated: true)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
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
                if model.canControlPlayback {
                    playbackControls
                }
                HStack(spacing: 10) {
                    if let url = track.appleMusicURL {
                        Link("Open in \(track.platform.rawValue)", destination: url)
                            .presenceButton(prominent: true)
                    }
                    Menu {
                        if !model.demoModeEnabled {
                            Button("Reload Album Artwork", systemImage: "photo.badge.arrow.down") {
                                model.retryCurrentArtwork()
                            }
                        }
                        Button("Open Connection Settings", systemImage: "antenna.radiowaves.left.and.right") {
                            model.openSettings(.integrations)
                        }
                        Divider()
                        Button(model.isPrivate ? "End Private Mode" : "Go Private", systemImage: model.isPrivate ? "eye" : "eye.slash") {
                            model.isPrivate ? model.endPrivateMode() : model.setPrivate(until: nil)
                        }
                    } label: {
                        Label("More actions", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                            .frame(width: 26, height: 26)
                            .background(.white.opacity(0.10), in: .circle)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("More actions")
                }
                ScrobbleProgress(state: model.scrobblePresentation)
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

    private var playbackControls: some View {
        HStack(spacing: 10) {
            Button("Previous", systemImage: "backward.fill") { model.performPlaybackControl(.previous) }
                .labelStyle(.iconOnly)
                .presenceButton()
            Button(
                model.snapshot.state == .playing ? "Pause" : "Play",
                systemImage: model.snapshot.state == .playing ? "pause.fill" : "play.fill"
            ) { model.performPlaybackControl(.toggle) }
                .labelStyle(.iconOnly)
                .presenceButton(prominent: true)
                .keyboardShortcut(.space, modifiers: [])
            Button("Next", systemImage: "forward.fill") { model.performPlaybackControl(.next) }
                .labelStyle(.iconOnly)
                .presenceButton()
            Text("Control \(model.snapshot.track?.platform.rawValue ?? "playback")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
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
        if model.artworkLoadState == .available(.generatedPlaceholder) {
            return "Designed album placeholder for \(track.title)"
        }
        return model.artworkImage == nil ? "Album artwork unavailable for \(track.title)" : "Album artwork for \(track.title)"
    }

    private func heroArtwork(size: CGFloat, isPlaying: Bool) -> some View {
        ZStack {
            ArtworkView(
                image: model.artworkImage,
                size: size,
                accessibilityDescription: artworkAccessibilityDescription,
                placeholderText: artworkPlaceholder
            )
            .presenceHeroGlow(active: isPlaying)
            .overlay(alignment: .bottomTrailing) {
                Label(
                    model.snapshot.state == .playing ? "Playing" : "Paused",
                    systemImage: model.snapshot.state == .playing ? "waveform" : "pause.fill"
                )
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: .capsule)
                .padding(size * 0.045)
            }
        }
        .id(currentTrackIdentifier)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var artworkPlaceholder: String? {
        guard let track = model.snapshot.track else { return nil }
        let words = track.album?.isEmpty == false ? track.album!.split(separator: " ") : track.title.split(separator: " ")
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? nil : String(letters).uppercased()
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
                    colors: [theme.secondaryColor.opacity(0.18), theme.primaryColor.opacity(0.12), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            Rectangle().fill(theme.darkBackground.opacity(0.52))
            RadialGradient(
                colors: [theme.secondaryColor.opacity(0.20), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 560
            )
            RadialGradient(
                colors: [theme.primaryColor.opacity(0.18), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 520
            )
        }
        .clipped()
    }

    private var discordRecoveryTitle: String? {
        guard model.preferences.discordEnabled else { return nil }
        return switch model.discordStatus {
        case .offline: "Open Discord"
        case .failed: "Try Again"
        default: nil
        }
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
    var placeholderText: String? = nil
    @Environment(\.appTheme) private var theme

    init(data: Data?, size: CGFloat, accessibilityDescription: String? = nil, placeholderText: String? = nil) {
        self.data = data
        image = nil
        self.size = size
        self.accessibilityDescription = accessibilityDescription
        self.placeholderText = placeholderText
    }

    init(image: NSImage?, size: CGFloat, accessibilityDescription: String? = nil, placeholderText: String? = nil) {
        data = nil
        self.image = image
        self.size = size
        self.accessibilityDescription = accessibilityDescription
        self.placeholderText = placeholderText
    }

    var body: some View {
        Group {
            if let image = image ?? data.flatMap(NSImage.init(data:)) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [theme.darkBackground, theme.darkBackground.mixed(with: .black, amount: 0.35), theme.primaryColor.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    if let placeholderText {
                        Text(placeholderText)
                            .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                    } else {
                        BrandMark()
                            .padding(size * 0.2)
                    }
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
    @Environment(\.appTheme) private var theme
    var body: some View {
        if let state {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(state.label, systemImage: symbol(for: state)).font(.subheadline.weight(.semibold))
                    Spacer()
                    if case .listening(_, let remaining) = state { Text("\(remaining.formattedDuration) to go").font(.caption).foregroundStyle(.secondary) }
                }
                switch state {
                case .listening(let progress, _): ProgressView(value: progress).tint(theme.accentGradient)
                case .ineligible(let reason): Text(reason).font(.caption).foregroundStyle(.secondary)
                default: EmptyView()
                }
            }
            .padding(12)
            .background(theme.primaryColor.opacity(0.08), in: .rect(cornerRadius: BrandRadius.md, style: .continuous))
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
        status.tintColor
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
                HStack(spacing: 5) {
                    Circle()
                        .fill(headerStatusColor)
                        .frame(width: 6, height: 6)
                    Text(headerDetail)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PresenceFM, \(headerDetail)")
    }

    private var headerDetail: String {
        if model.isPrivate { return "Private Mode active" }
        if model.snapshot.state == .playing, let platform = model.snapshot.track?.platform {
            return "Listening on \(platform.rawValue)"
        }
        return "Watching for music"
    }

    private var headerStatusColor: Color {
        if model.isPrivate { return BrandColors.warning }
        return model.snapshot.state == .playing ? BrandColors.success : BrandColors.neutral
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
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.primaryColor)
                    .frame(width: 38, height: 38)
                    .background(theme.subtleAccent(for: colorScheme), in: .rect(cornerRadius: 11))
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusLabelOverride ?? status.presentationLabel)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.11), in: .capsule)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(BrandTypography.cardTitle)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if let statusDetail = status.detailLabel, statusLabelOverride == nil {
                    Text(statusDetail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
            if let recoveryTitle {
                Button(recoveryTitle, action: recoveryAction)
                    .presenceButton(prominent: true)
                    .accessibilityHint("Attempts to recover the \(title) connection")
                    .accessibilityIdentifier("recovery.\(recoveryIdentifier)")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .padding(15)
        .presenceCard(elevated: true)
        .accessibilityElement(children: .contain)
    }

    @Environment(\.colorScheme) private var colorScheme

    private var statusColor: Color {
        status.tintColor
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
        return status.tintColor
    }
}

struct SidebarPrivacyControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.isPrivate ? "Private Mode is on" : "Go Private", systemImage: model.isPrivate ? "eye.slash.fill" : "eye.slash")
                .font(.callout.weight(.semibold))
            Text(model.isPrivate ? privateDetail : "Pause Discord sharing and Last.fm scrobbling.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PrivacyControls()
        }
        .padding(12)
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
                    action: { model.openSettings(.integrations) }
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
        .navigationTitle("Pending Plays")
        .overlay {
            if queuedRecords.isEmpty {
                ContentUnavailableView {
                    Label("Everything Is Synced", systemImage: "checkmark.circle")
                } description: {
                    Text("If Last.fm is unavailable, finished plays wait here and retry automatically.")
                }
            }
        }
        .confirmationDialog(
            "Remove this pending play?",
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
            Text("This stops PresenceFM from retrying “\(removal.title)” with Last.fm.")
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
                Text("\(count) \(count == 1 ? "play needs" : "plays need") attention")
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
    @State private var showsTechnicalDetails = false
    @State private var artworkCacheSummary = "Loading…"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Connections at a glance")
                        .font(BrandTypography.sectionTitle)
                    Text("See what PresenceFM can detect and share. If something needs attention, you can fix it here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190, maximum: 320), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    SupportStatusCard(
                        title: model.playbackServiceName,
                        detail: "Music detection",
                        symbol: "music.note",
                        status: model.musicStatus,
                        actionTitle: model.musicStatus == .awaitingPermission ? "Allow Access" : nil,
                        action: model.openAutomationSettings
                    )
                    SupportStatusCard(
                        title: "Discord",
                        detail: "Activity sharing",
                        symbol: "bubble.left.and.bubble.right",
                        status: model.discordStatus,
                        actionTitle: discordActionTitle,
                        action: model.refreshDiscord
                    )
                    SupportStatusCard(
                        title: "Last.fm",
                        detail: "Listening history sync",
                        symbol: "dot.radiowaves.left.and.right",
                        status: model.lastFMStatus,
                        actionTitle: lastFMActionTitle,
                        action: { model.openSettings(.integrations) }
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Need help?", systemImage: "lifepreserver")
                        .font(.headline)
                    Text("Copy a privacy-safe report to include when asking for support. It leaves out credentials, usernames, and listening details.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Copy Support Report", systemImage: "doc.on.doc") {
                        model.copyDiagnosticReport()
                    }
                    .presenceButton(prominent: true)
                    if !model.diagnosticCopyStatus.isEmpty {
                        Text(model.diagnosticCopyStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .presenceCard(elevated: true)

                DisclosureGroup(isExpanded: $showsTechnicalDetails) {
                    VStack(alignment: .leading, spacing: 18) {
                        technicalSystemDetails
                        technicalPollingDetails
                        technicalExportDetails
                        technicalLogDetails
                        technicalHealthDetails
                    }
                    .padding(.top, 14)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Technical details")
                            .font(.headline)
                        Text("Performance measurements, diagnostic logs, and connection history")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .presenceCard()
            }
            .frame(maxWidth: 980)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Status & Support")
        .task {
            let metrics = await model.artworkCacheMetrics()
            artworkCacheSummary = "\(metrics.memoryEntries) in memory · \(metrics.diskEntries) on disk"
        }
    }

    private var discordActionTitle: String? {
        guard model.preferences.discordEnabled, !model.discordStatus.isConnected, model.discordStatus != .connecting else { return nil }
        return "Try Again"
    }

    private var lastFMActionTitle: String? {
        switch model.lastFMStatus {
        case .authorizationExpired, .failed: "Open Settings"
        default: nil
        }
    }

    private var technicalSystemDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App & System").font(.subheadline.weight(.semibold))
            LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
            LabeledContent("PresenceFM", value: "\(ReleaseConfiguration.version) (\(ReleaseConfiguration.build))")
            LabeledContent("Artwork cache", value: artworkCacheSummary)
            if model.snapshot.track != nil, model.artworkImage == nil {
                Button("Retry Current Artwork", systemImage: "arrow.clockwise") {
                    model.retryCurrentArtwork()
                }
            }
        }
    }

    private var technicalPollingDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Playback Check Performance").font(.subheadline.weight(.semibold))
            LabeledContent("Latest check", value: model.playbackPollMetrics.totalDuration.formatted(.number.precision(.fractionLength(1...1))) + " s")
            ForEach(PlaybackProviderID.allCases) { provider in
                if let duration = model.playbackPollMetrics.providerDurations[provider] {
                    LabeledContent(provider.displayName, value: "\(Int((duration * 1_000).rounded())) ms")
                }
            }
        }
    }

    private var technicalExportDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verification Snapshot").font(.subheadline.weight(.semibold))
            HStack {
                Button("Copy Snapshot", systemImage: "doc.on.doc", action: model.copyVerificationReport)
                Button("Save Snapshot…", systemImage: "square.and.arrow.down", action: model.saveVerificationReport)
            }
            Text(model.verificationExportStatus.isEmpty ? "Exports app and connection health without track metadata, usernames, credentials, or file paths." : model.verificationExportStatus)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var technicalLogDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Diagnostic Messages").font(.subheadline.weight(.semibold))
            if records.isEmpty {
                Text("No diagnostic messages recorded.").foregroundStyle(.secondary)
            } else {
                ForEach(records.prefix(12)) { record in
                    Text("[\(record.category)] \(record.message)").font(.caption.monospaced())
                }
            }
        }
    }

    private var technicalHealthDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Connection Changes").font(.subheadline.weight(.semibold))
            if healthEvents.isEmpty {
                Text("No connection changes recorded.").foregroundStyle(.secondary)
            } else {
                ForEach(healthEvents.prefix(12)) { event in
                    HStack {
                        Text(IntegrationID(rawValue: event.integrationRaw)?.displayName ?? "Integration")
                        Spacer()
                        Text(IntegrationState(rawValue: event.stateRaw)?.rawValue.capitalized ?? event.stateRaw.capitalized)
                        Text(event.timestamp, style: .relative).foregroundStyle(.secondary)
                    }.font(.caption)
                }
            }
        }
    }
}

private struct SupportStatusCard: View {
    let title: String
    let detail: String
    let symbol: String
    let status: ServiceStatus
    let actionTitle: String?
    let action: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.primaryColor)
                    .frame(width: 36, height: 36)
                    .background(theme.subtleAccent(for: colorScheme), in: .rect(cornerRadius: 10))
                Spacer()
                Circle().fill(statusColor).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Text(status.presentationLabel)
                .font(.callout.weight(.semibold))
                .foregroundStyle(statusColor)
            if let statusDetail = status.detailLabel {
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .presenceButton(prominent: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .leading)
        .padding(16)
        .presenceCard(elevated: true)
        .accessibilityElement(children: .contain)
    }

    private var statusColor: Color {
        status.tintColor
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
                Button("Open Data Settings") { model.openSettings(.data) }
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
