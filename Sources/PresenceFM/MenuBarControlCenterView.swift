import AppKit
import SwiftData
import SwiftUI

struct MenuBarControlCenterView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appTheme) private var theme
    @State private var seekPosition: TimeInterval = 0
    @State private var isSeeking = false

    var body: some View {
        @Bindable var preferences = model.preferences
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

            ScrollView {
                VStack(spacing: 14) {
                    nowPlayingHero
                    if preferences.menuBarExpanded {
                        serviceGrid(preferences: preferences)
                        MenuBarWeeklyRecapView()
                    } else {
                        compactServiceStatus
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(width: 410, height: preferences.menuBarExpanded ? 590 : 430)
        .presencePanelBackground()
        .task { model.start() }
        .onChange(of: model.snapshot.position) { _, position in
            if !isSeeking { seekPosition = position }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            BrandMark()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("PresenceFM")
                    .font(.headline)
                Text(model.snapshot.state == .playing ? "Listening now" : "Ready in the background")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.preferences.menuBarExpanded.toggle()
            } label: {
                Image(systemName: model.preferences.menuBarExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(model.preferences.menuBarExpanded ? "Use Compact Menu" : "Use Expanded Menu")
            .accessibilityLabel(model.preferences.menuBarExpanded ? "Use compact menu" : "Use expanded menu")
            privacyMenu
        }
    }

    private var privacyMenu: some View {
        Menu {
            if model.isPrivate {
                Button("Resume Sharing", systemImage: "eye") { model.endPrivateMode() }
            } else {
                Button("Private for 15 Minutes") { model.setPrivate(until: .now.addingTimeInterval(900)) }
                Button("Private for 1 Hour") { model.setPrivate(until: .now.addingTimeInterval(3_600)) }
                Button("Private Until Resumed") { model.setPrivate(until: nil) }
            }
        } label: {
            Label(model.isPrivate ? "Private" : "Sharing", systemImage: model.isPrivate ? "eye.slash.fill" : "antenna.radiowaves.left.and.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.isPrivate ? BrandColors.warning : theme.primaryColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((model.isPrivate ? BrandColors.warning : theme.primaryColor).opacity(0.12), in: .capsule)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(model.isPrivate ? "Private Mode active" : "Sharing controls")
    }

    private var nowPlayingHero: some View {
        ZStack {
            heroBackdrop
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    ArtworkView(image: model.artworkImage, size: 104)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(playbackEyebrow)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.secondaryColor)
                            .textCase(.uppercase)
                        Text(model.snapshot.track?.title ?? "Nothing Playing")
                            .font(.title3.bold())
                            .lineLimit(2)
                        Text(model.snapshot.track?.artist ?? "Start music in a supported player")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let album = model.snapshot.track?.album, !album.isEmpty {
                            Text(album)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if let track = model.snapshot.track, track.supportsFiniteProgress {
                    if model.canControlPlayback {
                        seekControl(duration: track.duration)
                    } else {
                        PlaybackProgress(snapshot: model.snapshot, duration: track.duration)
                    }
                }

                if model.canControlPlayback {
                    playbackControls
                } else if model.snapshot.track == nil {
                    Button("Open Dashboard", systemImage: "rectangle.on.rectangle") {
                        NSApp.showDashboard(using: openWindow)
                    }
                    .presenceButton(prominent: true)
                }
            }
            .padding(16)
        }
        .clipShape(.rect(cornerRadius: BrandRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BrandRadius.xl, style: .continuous)
                .strokeBorder(theme.secondaryColor.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: theme.primaryColor.opacity(0.16), radius: 22, y: 10)
        .environment(\.colorScheme, .dark)
    }

    private var heroBackdrop: some View {
        ZStack {
            if let image = model.artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 42)
                    .scaleEffect(1.25)
                    .opacity(0.26)
            }
            LinearGradient(
                colors: [theme.darkBackground.opacity(0.96), theme.primaryColor.opacity(0.28), theme.darkBackground.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 16) {
            volumeButton(amount: -10, symbol: "speaker.minus.fill", label: "Lower Volume")
            playbackButton(.previous)
            Button {
                model.performPlaybackControl(.toggle)
            } label: {
                Image(systemName: model.snapshot.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(theme.accentGradient, in: .circle)
                    .shadow(color: theme.primaryColor.opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .help(model.snapshot.state == .playing ? "Pause" : "Play")
            playbackButton(.next)
            volumeButton(amount: 10, symbol: "speaker.plus.fill", label: "Raise Volume")
        }
        .frame(maxWidth: .infinity)
    }

    private func volumeButton(amount: Int, symbol: String, label: String) -> some View {
        Button {
            model.adjustPlaybackVolume(by: amount)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func seekControl(duration: TimeInterval) -> some View {
        VStack(spacing: 4) {
            Slider(value: $seekPosition, in: 0...max(duration, 1)) { editing in
                isSeeking = editing
                if !editing { model.seekPlayback(to: seekPosition) }
            }
            .tint(theme.primaryColor)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(Int(seekPosition)) seconds of \(Int(duration)) seconds")
            HStack {
                Text(durationLabel(seekPosition))
                Spacer()
                Text("−\(durationLabel(max(0, duration - seekPosition)))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func durationLabel(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func playbackButton(_ command: PlaybackControlCommand) -> some View {
        Button {
            model.performPlaybackControl(command)
        } label: {
            Image(systemName: command.symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.08), in: .circle)
        }
        .buttonStyle(.plain)
        .help(command == .previous ? "Previous Track" : "Next Track")
    }

    private func serviceGrid(preferences: Preferences) -> some View {
        HStack(spacing: 10) {
            MenuBarServiceTile(
                name: "Discord",
                symbol: "bubble.left.and.bubble.right.fill",
                status: model.discordStatus,
                isEnabled: Binding(
                    get: { preferences.discordEnabled },
                    set: { model.setDiscordEnabled($0) }
                )
            )
            MenuBarServiceTile(
                name: "Last.fm",
                symbol: "dot.radiowaves.left.and.right",
                status: model.lastFMStatus,
                isEnabled: Binding(
                    get: { preferences.lastFMEnabled },
                    set: { model.setLastFMEnabled($0) }
                )
            )
        }
    }

    private var compactServiceStatus: some View {
        HStack(spacing: 12) {
            compactStatus("Discord", model.discordStatus)
            Divider().frame(height: 22)
            compactStatus("Last.fm", model.lastFMStatus)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .presenceCard()
    }

    private func compactStatus(_ name: String, _ status: ServiceStatus) -> some View {
        HStack(spacing: 6) {
            Circle().fill(menuStatusColor(status)).frame(width: 7, height: 7)
            Text(name).font(.caption.weight(.semibold))
            Text(status.presentationLabel).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func menuStatusColor(_ status: ServiceStatus) -> Color {
        status.tintColor
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Dashboard", systemImage: "rectangle.grid.2x2") {
                NSApp.showDashboard(using: openWindow)
            }
            .accessibilityIdentifier("menu.dashboard")
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("menu.settings")
            Spacer()
            Button("Quit", systemImage: "power") {
                model.shutdown()
                NSApp.terminate(nil)
            }
            .labelStyle(.iconOnly)
            .help("Quit PresenceFM")
        }
        .presenceButton()
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private var playbackEyebrow: String {
        switch model.snapshot.state {
        case .playing: model.snapshot.track?.platform.rawValue ?? "Now Playing"
        case .paused: "Paused"
        case .stopped: "PresenceFM is ready"
        }
    }
}

private struct MenuBarServiceTile: View {
    let name: String
    let symbol: String
    let status: ServiceStatus
    @Binding var isEnabled: Bool
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(theme.primaryColor)
                    .frame(width: 28, height: 28)
                    .background(theme.primaryColor.opacity(0.12), in: .rect(cornerRadius: 8))
                Spacer()
                Toggle(name, isOn: $isEnabled)
                    .labelsHidden()
                    .controlSize(.small)
            }
            Text(name)
                .font(.callout.weight(.semibold))
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(status.presentationLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presenceCard()
        .accessibilityElement(children: .contain)
    }

    private var statusColor: Color {
        status.tintColor
    }
}

private struct MenuBarWeeklyRecapView: View {
    @Query(sort: \ActivityRecord.startedAt, order: .reverse) private var records: [ActivityRecord]
    @Environment(\.appTheme) private var theme

    var body: some View {
        let recap = WeeklyListeningRecap(records: records)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("This Week", systemImage: "sparkles")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.primaryColor)
                Spacer()
                if recap.listens > 0 {
                    Button("Copy Recap", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(recap.shareText, forType: .string)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Copy Weekly Recap")
                }
            }
            HStack(spacing: 0) {
                recapMetric(recap.listens.formatted(), "listens")
                Divider().frame(height: 30)
                recapMetric(recap.minutes.formatted(), "minutes")
                Divider().frame(height: 30)
                recapMetric(recap.uniqueArtists.formatted(), "artists")
            }
            if let artist = recap.topArtist {
                Text("Top artist · \(artist)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .presenceCard()
    }

    private func recapMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
